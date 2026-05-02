CREATE TABLE IF NOT EXISTS jobs (
    id        SERIAL PRIMARY KEY,
    user_email VARCHAR(255) NOT NULL,
    file_path  TEXT NOT NULL,
    status     VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw_text (
    id      SERIAL PRIMARY KEY,
    job_id  INTEGER REFERENCES jobs(id) ON DELETE CASCADE,
    content TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS invoices (
    id             SERIAL PRIMARY KEY,
    job_id         INTEGER REFERENCES jobs(id) ON DELETE CASCADE,
    invoice_number VARCHAR(100),
    vendor         VARCHAR(255),
    invoice_date   VARCHAR(50),
    total          DECIMAL(10,2)
);

CREATE TABLE IF NOT EXISTS line_items (
    id          SERIAL PRIMARY KEY,
    invoice_id  INTEGER REFERENCES invoices(id) ON DELETE CASCADE,
    description TEXT,
    amount      DECIMAL(10,2)
);
