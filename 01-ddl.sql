SET client_encoding = 'UTF8';
SET client_min_messages = warning;

-- ============================================================================
-- 1) room_type : ประเภทห้องพัก
-- ============================================================================
CREATE TABLE room_type (
    room_type_id   SERIAL PRIMARY KEY,            
    type_name      VARCHAR(50)  NOT NULL,          
    base_price     NUMERIC(10,2) NOT NULL,         
    description    TEXT                            
);


-- ============================================================================
-- 2) room : ข้อมูลห้องพัก
-- ============================================================================
CREATE TABLE room (
    room_id        SERIAL PRIMARY KEY,
    room_number    VARCHAR(10)  NOT NULL UNIQUE,   
    floor          INT          NOT NULL,           
    room_type_id   INT          NOT NULL,          
    monthly_rate   NUMERIC(10,2) NOT NULL,          
    status         VARCHAR(20)  NOT NULL DEFAULT 'ว่าง', 
    CONSTRAINT fk_room_type
        FOREIGN KEY (room_type_id) REFERENCES room_type(room_type_id),
    CONSTRAINT chk_room_status
        CHECK (status IN ('ว่าง', 'ไม่ว่าง', 'ปิดปรับปรุง'))
);


-- ============================================================================
-- 3) tenant : ข้อมูลผู้เช่า
-- ============================================================================
CREATE TABLE tenant (
    tenant_id      SERIAL PRIMARY KEY,
    full_name      VARCHAR(100) NOT NULL,          
    id_card_no     VARCHAR(13)  NOT NULL UNIQUE,   
    phone          VARCHAR(10),                    
    email          VARCHAR(100),                   
    created_at     TIMESTAMP    NOT NULL DEFAULT NOW()  
);


-- ============================================================================
-- 4) booking : การจองห้องพัก
-- ============================================================================
CREATE TABLE booking (
    booking_id     SERIAL PRIMARY KEY,
    room_id        INT          NOT NULL,          
    tenant_id      INT          NOT NULL,         
    booking_date   DATE         NOT NULL DEFAULT CURRENT_DATE,  
    move_in_date   DATE         NOT NULL,         
    status         VARCHAR(20)  NOT NULL DEFAULT 'รอดำเนินการ',  
    CONSTRAINT fk_booking_room
        FOREIGN KEY (room_id) REFERENCES room(room_id),
    CONSTRAINT fk_booking_tenant
        FOREIGN KEY (tenant_id) REFERENCES tenant(tenant_id)
);

-- ============================================================================
-- 5) contract : สัญญาเช่า
-- ============================================================================
CREATE TABLE contract (
    contract_id    SERIAL PRIMARY KEY,
    booking_id     INT          NOT NULL UNIQUE,   
    start_date     DATE         NOT NULL,          
    end_date       DATE         NOT NULL,         
    deposit        NUMERIC(10,2) NOT NULL,       
    CONSTRAINT fk_contract_booking
        FOREIGN KEY (booking_id) REFERENCES booking(booking_id),
    CONSTRAINT chk_contract_dates
        CHECK (end_date > start_date)
);


-- ============================================================================
-- 6) staff : ผู้ดูแล / พนักงาน / ช่าง
-- ============================================================================
CREATE TABLE staff (
    staff_id       SERIAL PRIMARY KEY,
    full_name      VARCHAR(100) NOT NULL,        
    position       VARCHAR(50)  NOT NULL,         
    phone          VARCHAR(10)                    


-- ============================================================================
-- 7) utility_meter : มิเตอร์น้ำและไฟ
-- ============================================================================
CREATE TABLE utility_meter (
    meter_id       SERIAL PRIMARY KEY,
    room_id        INT          NOT NULL,          
    meter_month    DATE         NOT NULL,        
    water_unit     NUMERIC(10,2) NOT NULL DEFAULT 0, 
    electric_unit  NUMERIC(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_meter_room
        FOREIGN KEY (room_id) REFERENCES room(room_id),
    CONSTRAINT uq_meter_room_month
        UNIQUE (room_id, meter_month)
);


-- ============================================================================
-- 8) invoice : ใบแจ้งหนี้ (ค่าเช่า ค่าน้ำ ค่าไฟ)
-- ============================================================================
CREATE TABLE invoice (
    invoice_id      SERIAL PRIMARY KEY,
    contract_id     INT          NOT NULL,          
    meter_id        INT,                             
    invoice_date    DATE         NOT NULL DEFAULT CURRENT_DATE, 
    due_date        DATE         NOT NULL,          
    rent_amount     NUMERIC(10,2) NOT NULL DEFAULT 0, 
    water_amount    NUMERIC(10,2) NOT NULL DEFAULT 0, 
    electric_amount NUMERIC(10,2) NOT NULL DEFAULT 0, 
    total_amount    NUMERIC(10,2) GENERATED ALWAYS AS (rent_amount + water_amount + electric_amount) STORED,
    status          VARCHAR(20)  NOT NULL DEFAULT 'ค้างชำระ', 
    CONSTRAINT fk_invoice_contract
        FOREIGN KEY (contract_id) REFERENCES contract(contract_id),
    CONSTRAINT fk_invoice_meter
        FOREIGN KEY (meter_id) REFERENCES utility_meter(meter_id)
);


-- ============================================================================
-- 9) payment : การชำระเงิน (แบ่งงวดได้)
-- ============================================================================
CREATE TABLE payment (
    payment_id     SERIAL PRIMARY KEY,
    invoice_id     INT          NOT NULL,         
    payment_date   DATE         NOT NULL DEFAULT CURRENT_DATE, 
    amount         NUMERIC(10,2) NOT NULL,          
    payment_type   VARCHAR(20)  NOT NULL,       
    CONSTRAINT fk_payment_invoice
        FOREIGN KEY (invoice_id) REFERENCES invoice(invoice_id),
    CONSTRAINT chk_payment_amount
        CHECK (amount > 0)
);


-- ============================================================================
-- 10) repair_request : รายการแจ้งซ่อม
-- ============================================================================
CREATE TABLE repair_request (
    repair_id      SERIAL PRIMARY KEY,
    room_id        INT          NOT NULL,          
    staff_id       INT,                              
    request_date   DATE         NOT NULL DEFAULT CURRENT_DATE,  
    description    TEXT         NOT NULL,          
    status         VARCHAR(20)  NOT NULL DEFAULT 'รอดำเนินการ',  
    CONSTRAINT fk_repair_room
        FOREIGN KEY (room_id) REFERENCES room(room_id),
    CONSTRAINT fk_repair_staff
        FOREIGN KEY (staff_id) REFERENCES staff(staff_id)
);
