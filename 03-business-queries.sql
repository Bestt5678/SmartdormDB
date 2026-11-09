-- =====================================================================
--  SmartDorm Database — 03-business-queries.sql
--  คำสั่งสืบค้นตอบโจทย์ทางธุรกิจของหอพัก (15 ข้อ)
--
--  ต้องรันหลัง 01-ddl.sql และ 02-sample-data.sql
--  ทุกคำสั่งเป็น SELECT อย่างเดียว ไม่แก้ไขข้อมูล
--
--  "วันที่รายงาน" กำหนดไว้ใน CTE ชื่อ params = 2026-11-09 (วันที่ของชุดข้อมูลตัวอย่าง)
--  เพื่อให้ผลลัพธ์คงที่ทุกครั้งที่รัน ถ้าใช้งานจริงให้เปลี่ยนเป็น CURRENT_DATE
-- =====================================================================

SET client_encoding = 'UTF8';
\pset null '-'


-- ---------------------------------------------------------------------
-- Q1. อัตราการเข้าพักแยกตามชั้น — ชั้นไหนว่างมาก ควรทำโปรโมชันหรือไม่
--     เทคนิค: GROUP BY + FILTER, ROLLUP สำหรับแถวรวม
-- ---------------------------------------------------------------------
\echo '=== Q1 อัตราการเข้าพักแยกตามชั้น ==='
SELECT COALESCE(floor::text, 'รวมทั้งหอ')                     AS ชั้น,
       COUNT(*)                                               AS ห้องทั้งหมด,
       COUNT(*) FILTER (WHERE status = 'ไม่ว่าง')               AS มีผู้เช่า,
       COUNT(*) FILTER (WHERE status = 'ว่าง')                 AS ว่าง,
       COUNT(*) FILTER (WHERE status = 'ปิดปรับปรุง')           AS ปิดปรับปรุง,
       ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'ไม่ว่าง')
             / NULLIF(COUNT(*) FILTER (WHERE status <> 'ปิดปรับปรุง'), 0), 1) AS อัตราเข้าพัก_ร้อยละ
FROM room
GROUP BY ROLLUP (floor)
ORDER BY floor NULLS LAST;


-- ---------------------------------------------------------------------
-- Q2. ยอดเรียกเก็บเทียบยอดเก็บได้จริง รายเดือน (อัตราการจัดเก็บ)
--     เทคนิค: subquery รวมยอดชำระ, LEFT JOIN, window SUM สะสม
-- ---------------------------------------------------------------------
\echo '=== Q2 ยอดเรียกเก็บ vs ยอดเก็บได้ รายเดือน ==='
WITH paid AS (
    SELECT invoice_id, SUM(amount) AS paid_amount
    FROM payment
    GROUP BY invoice_id
)
SELECT to_char(i.invoice_date, 'YYYY-MM')                          AS เดือนที่ออกบิล,
       COUNT(*)                                                    AS จำนวนใบแจ้งหนี้,
       SUM(i.total_amount)                                         AS ยอดเรียกเก็บ,
       SUM(COALESCE(p.paid_amount, 0))                             AS ยอดเก็บได้,
       SUM(i.total_amount - COALESCE(p.paid_amount, 0))            AS ยอดค้าง,
       ROUND(100 * SUM(COALESCE(p.paid_amount, 0)) / SUM(i.total_amount), 1) AS อัตราจัดเก็บ_ร้อยละ,
       SUM(SUM(COALESCE(p.paid_amount, 0))) OVER (ORDER BY to_char(i.invoice_date, 'YYYY-MM')) AS ยอดเก็บสะสม
FROM invoice i
LEFT JOIN paid p ON p.invoice_id = i.invoice_id
GROUP BY to_char(i.invoice_date, 'YYYY-MM')
ORDER BY 1;


-- ---------------------------------------------------------------------
-- Q3. รายได้ค่าเช่าตามประเภทห้อง และรายได้เฉลี่ยต่อห้อง — ประเภทไหนคุ้มที่สุด
--     เทคนิค: JOIN 5 ตาราง, RANK()
-- ---------------------------------------------------------------------
\echo '=== Q3 รายได้ตามประเภทห้อง (ยอดที่เก็บได้จริงในปี 2026) ==='
WITH revenue AS (
    SELECT r.room_type_id,
           SUM(p.amount) AS revenue
    FROM payment  p
    JOIN invoice  i ON i.invoice_id = p.invoice_id
    JOIN contract c ON c.contract_id = i.contract_id
    JOIN booking  b ON b.booking_id = c.booking_id
    JOIN room     r ON r.room_id = b.room_id
    WHERE p.payment_date >= DATE '2026-01-01'
    GROUP BY r.room_type_id
)
SELECT rt.type_name                                        AS ประเภทห้อง,
       COUNT(r.room_id)                                     AS จำนวนห้อง,
       COALESCE(rv.revenue, 0)                              AS รายได้รวม,
       ROUND(COALESCE(rv.revenue, 0) / COUNT(r.room_id), 2) AS รายได้เฉลี่ยต่อห้อง,
       RANK() OVER (ORDER BY COALESCE(rv.revenue, 0) / COUNT(r.room_id) DESC) AS อันดับ
FROM room_type rt
JOIN room r ON r.room_type_id = rt.room_type_id
LEFT JOIN revenue rv ON rv.room_type_id = rt.room_type_id
GROUP BY rt.room_type_id, rt.type_name, rv.revenue
ORDER BY อันดับ;


-- ---------------------------------------------------------------------
-- Q4. รายชื่อผู้เช่าที่ค้างชำระเกินกำหนด เรียงตามยอดค้าง — ใช้ติดตามทวงถาม
--     เทคนิค: CTE, JOIN 5 ตาราง, HAVING, string_agg
-- ---------------------------------------------------------------------
\echo '=== Q4 ผู้เช่าที่ค้างชำระเกินกำหนด ==='
WITH params AS (SELECT DATE '2026-11-09' AS today),
balance AS (
    SELECT i.invoice_id, i.contract_id, i.invoice_date, i.due_date,
           i.total_amount - COALESCE(SUM(p.amount), 0) AS outstanding
    FROM invoice i
    LEFT JOIN payment p ON p.invoice_id = i.invoice_id
    GROUP BY i.invoice_id
)
SELECT t.full_name                         AS ผู้เช่า,
       t.phone                             AS เบอร์โทร,
       r.room_number                       AS ห้อง,
       COUNT(*)                            AS จำนวนบิลค้าง,
       SUM(bl.outstanding)                 AS ยอดค้างรวม,
       MAX(pr.today - bl.due_date)         AS ค้างนานสุด_วัน,
       string_agg(to_char(bl.invoice_date, 'YYYY-MM'), ', ' ORDER BY bl.invoice_date) AS งวดที่ค้าง
FROM balance bl
CROSS JOIN params pr
JOIN contract c ON c.contract_id = bl.contract_id
JOIN booking  b ON b.booking_id = c.booking_id
JOIN tenant   t ON t.tenant_id = b.tenant_id
JOIN room     r ON r.room_id = b.room_id
WHERE bl.outstanding > 0
  AND bl.due_date < pr.today
GROUP BY t.tenant_id, t.full_name, t.phone, r.room_number
ORDER BY ยอดค้างรวม DESC;


-- ---------------------------------------------------------------------
-- Q5. อายุหนี้ (Aging report) — แบ่งยอดค้างตามจำนวนวันที่เกินกำหนด
--     เทคนิค: CASE จัดกลุ่ม, เปอร์เซ็นต์ด้วย window function
-- ---------------------------------------------------------------------
\echo '=== Q5 อายุหนี้ค้างชำระ ==='
WITH params AS (SELECT DATE '2026-11-09' AS today),
balance AS (
    SELECT i.due_date,
           i.total_amount - COALESCE(SUM(p.amount), 0) AS outstanding
    FROM invoice i
    LEFT JOIN payment p ON p.invoice_id = i.invoice_id
    GROUP BY i.invoice_id
),
aged AS (
    SELECT bl.outstanding,
           CASE
             WHEN pr.today - bl.due_date <= 30 THEN 1
             WHEN pr.today - bl.due_date <= 60 THEN 2
             ELSE 3
           END AS bucket
    FROM balance bl, params pr
    WHERE bl.outstanding > 0 AND bl.due_date < pr.today
)
SELECT CASE bucket WHEN 1 THEN '1-30 วัน' WHEN 2 THEN '31-60 วัน' ELSE 'เกิน 60 วัน' END AS ช่วงอายุหนี้,
       COUNT(*)          AS จำนวนบิล,
       SUM(outstanding)  AS ยอดค้าง,
       ROUND(100 * SUM(outstanding) / SUM(SUM(outstanding)) OVER (), 1) AS สัดส่วน_ร้อยละ
FROM aged
GROUP BY bucket
ORDER BY bucket;


-- ---------------------------------------------------------------------
-- Q6. ห้องที่ใช้ไฟฟ้าสูงผิดปกติ (> 1.5 เท่าของค่าเฉลี่ยห้องประเภทเดียวกันในเดือนเดียวกัน)
--     — อาจมีเครื่องใช้ไฟฟ้าผิดเงื่อนไข หรือแอร์/มิเตอร์ชำรุด
--     เทคนิค: window function AVG() OVER (PARTITION BY ...)
-- ---------------------------------------------------------------------
\echo '=== Q6 การใช้ไฟฟ้าเทียบห้องประเภทเดียวกัน ==='
WITH stats AS (
    SELECT r.room_number,
           rt.type_name,
           m.meter_month,
           m.electric_unit,
           AVG(m.electric_unit) OVER (PARTITION BY r.room_type_id, m.meter_month) AS avg_same_type
    FROM utility_meter m
    JOIN room r       ON r.room_id = m.room_id
    JOIN room_type rt ON rt.room_type_id = r.room_type_id
)
SELECT room_number                              AS ห้อง,
       type_name                                AS ประเภท,
       to_char(meter_month, 'YYYY-MM')          AS เดือน,
       electric_unit                            AS หน่วยไฟ,
       ROUND(avg_same_type, 1)                  AS ค่าเฉลี่ยประเภทนี้,
       ROUND(electric_unit / avg_same_type, 2)  AS เท่าของค่าเฉลี่ย,
       CASE WHEN electric_unit > 1.5 * avg_same_type THEN 'สูงผิดปกติ' ELSE '' END AS หมายเหตุ
FROM stats
ORDER BY เท่าของค่าเฉลี่ย DESC;


-- ---------------------------------------------------------------------
-- Q7. สัดส่วนค่าน้ำ-ค่าไฟในบิลของแต่ละห้อง — ห้องไหนค่าสาธารณูปโภคเป็นภาระมาก
--     เทคนิค: JOIN invoice กับ utility_meter, คำนวณร้อยละ
-- ---------------------------------------------------------------------
\echo '=== Q7 ค่าน้ำ-ไฟเทียบยอดบิล ==='
SELECT r.room_number                                       AS ห้อง,
       to_char(m.meter_month, 'YYYY-MM')                   AS รอบมิเตอร์,
       m.water_unit                                        AS หน่วยน้ำ,
       m.electric_unit                                     AS หน่วยไฟ,
       i.rent_amount                                       AS ค่าเช่า,
       i.water_amount + i.electric_amount                  AS ค่าน้ำไฟ,
       i.total_amount                                      AS ยอดบิล,
       ROUND(100 * (i.water_amount + i.electric_amount) / i.total_amount, 1) AS ค่าน้ำไฟ_ร้อยละ
FROM invoice i
JOIN utility_meter m ON m.meter_id = i.meter_id
JOIN room r          ON r.room_id = m.room_id
ORDER BY ค่าน้ำไฟ_ร้อยละ DESC;


-- ---------------------------------------------------------------------
-- Q8. สัญญาที่จะหมดภายใน 60 วัน พร้อมยอดหนี้คงค้าง
--     — ใช้ตัดสินใจต่อสัญญา / คืนเงินมัดจำ (หักหนี้ค้าง)
--     เทคนิค: LEFT JOIN LATERAL
-- ---------------------------------------------------------------------
\echo '=== Q8 สัญญาที่ใกล้หมดอายุ (60 วัน) ==='
WITH params AS (SELECT DATE '2026-11-09' AS today)
SELECT r.room_number                      AS ห้อง,
       t.full_name                        AS ผู้เช่า,
       c.end_date                         AS วันสิ้นสุดสัญญา,
       c.end_date - pr.today              AS เหลืออีก_วัน,
       c.deposit                          AS เงินมัดจำ,
       COALESCE(debt.outstanding, 0)      AS หนี้คงค้าง,
       c.deposit - COALESCE(debt.outstanding, 0) AS มัดจำคงเหลือ
FROM contract c
CROSS JOIN params pr
JOIN booking b ON b.booking_id = c.booking_id
JOIN tenant  t ON t.tenant_id = b.tenant_id
JOIN room    r ON r.room_id = b.room_id
LEFT JOIN LATERAL (
    SELECT SUM(i.total_amount - COALESCE((SELECT SUM(p.amount) FROM payment p
                                          WHERE p.invoice_id = i.invoice_id), 0)) AS outstanding
    FROM invoice i
    WHERE i.contract_id = c.contract_id
) debt ON TRUE
WHERE b.status = 'ยืนยันแล้ว'
  AND c.end_date BETWEEN pr.today AND pr.today + 60
ORDER BY c.end_date;


-- ---------------------------------------------------------------------
-- Q9. พฤติกรรมการชำระเงินของผู้เช่า — จ่ายตรงเวลา / จ่ายช้ากี่ครั้ง เฉลี่ยช้ากี่วัน
--     เทคนิค: JOIN, FILTER, AVG ของช่วงวัน
-- ---------------------------------------------------------------------
\echo '=== Q9 พฤติกรรมการชำระเงินของผู้เช่า ==='
SELECT t.full_name                                                AS ผู้เช่า,
       COUNT(*)                                                   AS ครั้งที่ชำระ,
       COUNT(*) FILTER (WHERE p.payment_date <= i.due_date)        AS ตรงเวลา,
       COUNT(*) FILTER (WHERE p.payment_date >  i.due_date)        AS ช้า,
       ROUND(AVG(p.payment_date - i.due_date)
             FILTER (WHERE p.payment_date > i.due_date), 1)       AS ช้าเฉลี่ย_วัน,
       SUM(p.amount)                                              AS ยอดชำระรวม
FROM payment p
JOIN invoice  i ON i.invoice_id = p.invoice_id
JOIN contract c ON c.contract_id = i.contract_id
JOIN booking  b ON b.booking_id = c.booking_id
JOIN tenant   t ON t.tenant_id = b.tenant_id
GROUP BY t.tenant_id, t.full_name
ORDER BY ช้า DESC, ผู้เช่า;


-- ---------------------------------------------------------------------
-- Q10. ภาระงานของช่างซ่อม และงานที่ยังไม่มีผู้รับผิดชอบ
--      เทคนิค: LEFT JOIN จาก staff เพื่อให้เห็นคนที่ไม่มีงาน, FILTER
-- ---------------------------------------------------------------------
\echo '=== Q10 ภาระงานช่างซ่อม ==='
SELECT s.full_name                                                     AS พนักงาน,
       s.position                                                      AS ตำแหน่ง,
       COUNT(rr.repair_id)                                             AS งานทั้งหมด,
       COUNT(rr.repair_id) FILTER (WHERE rr.status = 'เสร็จสิ้น')        AS เสร็จแล้ว,
       COUNT(rr.repair_id) FILTER (WHERE rr.status = 'กำลังดำเนินการ')   AS กำลังทำ
FROM staff s
LEFT JOIN repair_request rr ON rr.staff_id = s.staff_id
WHERE s.position = 'ช่างซ่อมบำรุง' OR rr.repair_id IS NOT NULL
GROUP BY s.staff_id, s.full_name, s.position
ORDER BY งานทั้งหมด DESC;

\echo '=== Q10b งานแจ้งซ่อมที่ยังไม่มีผู้รับผิดชอบ ==='
SELECT rr.repair_id, r.room_number AS ห้อง, rr.request_date AS วันที่แจ้ง, rr.description AS รายละเอียด
FROM repair_request rr
JOIN room r ON r.room_id = rr.room_id
WHERE rr.staff_id IS NULL AND rr.status = 'รอดำเนินการ'
ORDER BY rr.request_date;


-- ---------------------------------------------------------------------
-- Q11. สถานะงานแจ้งซ่อมแยกตามประเภทห้อง — ห้องประเภทไหนมีปัญหามาก งานค้างเท่าไร
--      เทคนิค: GROUP BY + FILTER, string_agg
-- ---------------------------------------------------------------------
\echo '=== Q11 สถานะงานแจ้งซ่อมตามประเภทห้อง ==='
SELECT rt.type_name                                               AS ประเภทห้อง,
       COUNT(*)                                                   AS งานทั้งหมด,
       COUNT(*) FILTER (WHERE rr.status = 'เสร็จสิ้น')              AS เสร็จสิ้น,
       COUNT(*) FILTER (WHERE rr.status = 'กำลังดำเนินการ')         AS กำลังดำเนินการ,
       COUNT(*) FILTER (WHERE rr.status = 'รอดำเนินการ')            AS รอดำเนินการ,
       string_agg(r.room_number || ': ' || rr.description, ' | ' ORDER BY rr.request_date) AS รายการ
FROM repair_request rr
JOIN room r       ON r.room_id = rr.room_id
JOIN room_type rt ON rt.room_type_id = r.room_type_id
GROUP BY rt.room_type_id, rt.type_name
ORDER BY งานทั้งหมด DESC;


-- ---------------------------------------------------------------------
-- Q12. สัดส่วนช่องทางการชำระเงิน — พิจารณาว่าควรรับเงินสดต่อหรือไม่
--      เทคนิค: window SUM() OVER () หาเปอร์เซ็นต์
-- ---------------------------------------------------------------------
\echo '=== Q12 สัดส่วนช่องทางการชำระเงิน ==='
SELECT payment_type                                              AS ช่องทาง,
       COUNT(*)                                                  AS จำนวนรายการ,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS สัดส่วนรายการ_ร้อยละ,
       SUM(amount)                                               AS ยอดเงิน,
       ROUND(100 * SUM(amount) / SUM(SUM(amount)) OVER (), 1)    AS สัดส่วนยอดเงิน_ร้อยละ
FROM payment
GROUP BY payment_type
ORDER BY ยอดเงิน DESC;


-- ---------------------------------------------------------------------
-- Q13. ผู้เช่าปัจจุบันที่ชำระครบและตรงเวลาทุกงวด — กลุ่มเป้าหมายส่วนลดต่อสัญญา
--      เทคนิค: NOT EXISTS (relational division แบบ "ทุกใบ")
-- ---------------------------------------------------------------------
\echo '=== Q13 ผู้เช่าปัจจุบันที่ชำระตรงเวลาทุกงวด ==='
WITH params AS (SELECT DATE '2026-11-09' AS today)
SELECT t.full_name   AS ผู้เช่า,
       r.room_number AS ห้อง,
       c.start_date  AS เริ่มเช่า,
       (SELECT COUNT(*) FROM invoice i WHERE i.contract_id = c.contract_id) AS จำนวนบิล
FROM contract c
CROSS JOIN params pr
JOIN booking b ON b.booking_id = c.booking_id
JOIN tenant  t ON t.tenant_id = b.tenant_id
JOIN room    r ON r.room_id = b.room_id
WHERE b.status = 'ยืนยันแล้ว'
  AND c.start_date <= pr.today - 90      -- เช่ามาแล้วอย่างน้อย 3 เดือน
  AND NOT EXISTS (
        -- ไม่มีบิลใดที่ครบกำหนดแล้ว แต่ยอดที่จ่ายภายในวันครบกำหนดยังไม่ครบ
        SELECT 1
        FROM invoice i
        WHERE i.contract_id = c.contract_id
          AND i.due_date < pr.today
          AND i.total_amount > (
                SELECT COALESCE(SUM(p.amount), 0)
                FROM payment p
                WHERE p.invoice_id = i.invoice_id
                  AND p.payment_date <= i.due_date)
      )
ORDER BY c.start_date;


-- ---------------------------------------------------------------------
-- Q14. ห้องว่างพร้อมให้จอง พร้อมราคาและเงินมัดจำ — ข้อมูลหน้าเว็บ
--      เทคนิค: JOIN, NOT EXISTS ตรวจการจองที่ค้างอยู่, GROUP BY สรุปตามประเภท
-- ---------------------------------------------------------------------
\echo '=== Q14 ห้องว่างพร้อมให้จอง (สรุปตามประเภทห้อง) ==='
SELECT rt.type_name                                     AS ประเภท,
       COUNT(*)                                         AS ห้องว่าง,
       MIN(r.monthly_rate)                              AS ค่าเช่าต่ำสุด,
       MAX(r.monthly_rate)                              AS ค่าเช่าสูงสุด,
       string_agg(r.room_number, ', ' ORDER BY r.room_number) AS เลขห้อง
FROM room r
JOIN room_type rt ON rt.room_type_id = r.room_type_id
WHERE r.status = 'ว่าง'
  AND NOT EXISTS (SELECT 1 FROM booking b
                  WHERE b.room_id = r.room_id
                    AND b.status IN ('รอดำเนินการ', 'ยืนยันแล้ว'))
GROUP BY rt.room_type_id, rt.type_name
ORDER BY ค่าเช่าต่ำสุด;


-- ---------------------------------------------------------------------
-- Q15. อัตราการยกเลิกการจอง และผู้เช่าที่กลับมาเช่าซ้ำ
--      เทคนิค: FILTER, subquery ใน FROM
-- ---------------------------------------------------------------------
\echo '=== Q15 สรุปการจอง ==='
SELECT COUNT(*)                                             AS การจองทั้งหมด,
       COUNT(*) FILTER (WHERE status = 'ยกเลิก')             AS ยกเลิก,
       ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'ยกเลิก') / COUNT(*), 1) AS อัตรายกเลิก_ร้อยละ,
       ROUND(AVG(move_in_date - booking_date), 1)           AS จองล่วงหน้าเฉลี่ย_วัน,
       (SELECT COUNT(*) FROM (
            SELECT tenant_id FROM booking
            WHERE status IN ('ยืนยันแล้ว', 'เสร็จสิ้น')
            GROUP BY tenant_id HAVING COUNT(*) >= 2) x)     AS ผู้เช่าเช่าซ้ำ
FROM booking;
