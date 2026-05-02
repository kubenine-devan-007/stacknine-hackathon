from app.parser import parse_invoice_fields

SAMPLE_TEXT = """Acme Corp
From: Acme Corp
Invoice #INV-2024-001
Date: 2024-03-15

Web Hosting          299.00
Support Plan         150.00
Setup Fee             50.00

TOTAL: 499.00"""

def test_parse_invoice_number():
    result = parse_invoice_fields(SAMPLE_TEXT)
    assert result["invoice_number"] == "INV-2024-001"

def test_parse_vendor():
    result = parse_invoice_fields(SAMPLE_TEXT)
    assert result["vendor"] == "Acme Corp"

def test_parse_date():
    result = parse_invoice_fields(SAMPLE_TEXT)
    assert result["invoice_date"] == "2024-03-15"

def test_parse_total():
    result = parse_invoice_fields(SAMPLE_TEXT)
    assert result["total"] == 499.00

def test_parse_line_items_count():
    result = parse_invoice_fields(SAMPLE_TEXT)
    assert len(result["line_items"]) == 3

def test_parse_line_item_amount():
    result = parse_invoice_fields(SAMPLE_TEXT)
    amounts = [i["amount"] for i in result["line_items"]]
    assert 299.00 in amounts
    assert 150.00 in amounts
    assert 50.00 in amounts

def test_parse_returns_none_fields_on_empty():
    result = parse_invoice_fields("")
    assert result["invoice_number"] is None
    assert result["total"] is None

from fastapi.testclient import TestClient
from unittest.mock import patch

def get_client():
    from app.main import app
    return TestClient(app)

def test_parse_endpoint_returns_200():
    client = get_client()
    with patch("app.main.db.get_raw_text", return_value=SAMPLE_TEXT), \
         patch("app.main.db.save_invoice"):
        response = client.post("/parse", json={"job_id": 1})
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_parse_endpoint_rejects_missing_job_id():
    client = get_client()
    response = client.post("/parse", json={})
    assert response.status_code == 422

def test_parse_health_endpoint():
    client = get_client()
    response = client.get("/health")
    assert response.status_code == 200
