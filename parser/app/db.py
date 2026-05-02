import psycopg2
from app.config import DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD

def get_conn():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
    )

def get_raw_text(job_id: int) -> str:
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT content FROM raw_text WHERE job_id = %s", (job_id,))
            row = cur.fetchone()
    finally:
        conn.close()
    if not row:
        raise ValueError(f"no raw text for job {job_id}")
    return row[0]

def save_invoice(job_id: int, fields: dict):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO invoices (job_id, invoice_number, vendor, invoice_date, total)
                   VALUES (%s, %s, %s, %s, %s) RETURNING id""",
                (job_id, fields.get("invoice_number"), fields.get("vendor"),
                 fields.get("invoice_date"), fields.get("total"))
            )
            invoice_id = cur.fetchone()[0]
            for item in fields.get("line_items", []):
                cur.execute(
                    "INSERT INTO line_items (invoice_id, description, amount) VALUES (%s, %s, %s)",
                    (invoice_id, item["description"], item["amount"])
                )
            cur.execute("UPDATE jobs SET status = 'done' WHERE id = %s", (job_id,))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
