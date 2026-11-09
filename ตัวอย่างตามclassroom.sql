SET client_encoding = 'UTF8';
\pset null '-'
-- =====================================================================
--  ตัวอย่าง query 5 ข้อ ตามเงื่อนไขที่กำหนด
--    ตัวอย่างที่ 1  GROUP BY
--    ตัวอย่างที่ 2  MIN, MAX, AVG
--    ตัวอย่างที่ 3  Subquery
--    ตัวอย่างที่ 4  JOIN
--    ตัวอย่างที่ 5  รวมทุกเงื่อนไข 
-- =====================================================================

-- ---------------------------------------------------------------------
-- GROUP BY
-- แต่ละชั้นมีห้องว่าง ห้องที่มีผู้เช่า และห้องปิดปรับปรุงกี่ห้อง
-- ---------------------------------------------------------------------
SELECT floor        AS ชั้น,
       status       AS สถานะ,
       COUNT(*)     AS จำนวนห้อง
FROM room
GROUP BY floor, status
ORDER BY floor, status;


-- ---------------------------------------------------------------------
-- MIN MAX AVG
-- ค่าเช่าต่ำสุด สูงสุด และเฉลี่ยของห้องแต่ละประเภท 
-- ---------------------------------------------------------------------
SELECT rt.type_name                    AS ประเภทห้อง,
       COUNT(*)                        AS จำนวนห้อง,
       MIN(r.monthly_rate)             AS ค่าเช่าต่ำสุด,
       MAX(r.monthly_rate)             AS ค่าเช่าสูงสุด,
       ROUND(AVG(r.monthly_rate), 2)   AS ค่าเช่าเฉลี่ย
FROM room r
JOIN room_type rt ON rt.room_type_id = r.room_type_id
GROUP BY rt.type_name
ORDER BY ค่าเช่าเฉลี่ย;


-- ---------------------------------------------------------------------
-- Subquery
-- ใบแจ้งหนี้ใบไหนที่ยอดชำระยังไม่ครบ และยังค้างอยู่เท่าไร
-- ---------------------------------------------------------------------
SELECT i.invoice_id    AS เลขที่บิล,
       i.due_date      AS ครบกำหนด,
       i.total_amount  AS ยอดบิล,
       (SELECT COALESCE(SUM(p.amount), 0)
          FROM payment p
         WHERE p.invoice_id = i.invoice_id)                    AS ชำระแล้ว,
       i.total_amount - (SELECT COALESCE(SUM(p.amount), 0)
                           FROM payment p
                          WHERE p.invoice_id = i.invoice_id)   AS ยอดค้าง
FROM invoice i
WHERE i.total_amount > (SELECT COALESCE(SUM(p.amount), 0)
                          FROM payment p
                         WHERE p.invoice_id = i.invoice_id)
ORDER BY ยอดค้าง DESC;


-- ---------------------------------------------------------------------
-- JOIN
-- รายชื่อผู้เช่าปัจจุบัน พร้อมห้อง ประเภทห้อง และวันสิ้นสุดสัญญา
-- ---------------------------------------------------------------------
SELECT t.full_name     AS ผู้เช่า,
       t.phone         AS เบอร์โทร,
       r.room_number   AS ห้อง,
       rt.type_name    AS ประเภทห้อง,
       r.monthly_rate  AS ค่าเช่า,
       c.start_date    AS เริ่มสัญญา,
       c.end_date      AS สิ้นสุดสัญญา
FROM tenant t
JOIN booking   b  ON b.tenant_id    = t.tenant_id
JOIN room      r  ON r.room_id      = b.room_id
JOIN room_type rt ON rt.room_type_id = r.room_type_id
JOIN contract  c  ON c.booking_id   = b.booking_id
WHERE b.status = 'ยืนยันแล้ว'
ORDER BY r.room_number;


-- ---------------------------------------------------------------------
-- ตัวอย่างที่ 5 (รวมทุกเงื่อนไข: JOIN + GROUP BY + HAVING + Subquery + CASE)
-- ห้องที่ใช้ไฟมากกว่าค่าเฉลี่ยของทั้งหอ พร้อมผู้เช่า ยอดค่าไฟ
--        และระดับการใช้ไฟ — ใช้ตรวจห้องที่อาจมีเครื่องใช้ไฟฟ้าเกินเงื่อนไข
-- ---------------------------------------------------------------------
SELECT r.room_number                   AS ห้อง,
       t.full_name                     AS ผู้เช่า,
       SUM(m.electric_unit)            AS หน่วยไฟ,
       SUM(i.electric_amount)          AS ค่าไฟ,
       CASE
         WHEN SUM(m.electric_unit) > 1.5 * (SELECT AVG(electric_unit) FROM utility_meter) THEN 'สูงมาก ควรตรวจสอบ'
         ELSE 'สูงกว่าค่าเฉลี่ย'
       END                             AS ระดับการใช้ไฟ
FROM utility_meter m
JOIN invoice  i ON i.meter_id    = m.meter_id
JOIN contract c ON c.contract_id = i.contract_id
JOIN booking  b ON b.booking_id  = c.booking_id
JOIN tenant   t ON t.tenant_id   = b.tenant_id
JOIN room     r ON r.room_id     = m.room_id
GROUP BY r.room_number, t.full_name
HAVING SUM(m.electric_unit) > (SELECT AVG(electric_unit) FROM utility_meter)
ORDER BY หน่วยไฟ DESC;

SELECT ROUND(AVG(electric_unit), 1) AS ไฟเฉลี่ยต่อห้อง FROM utility_meter;
