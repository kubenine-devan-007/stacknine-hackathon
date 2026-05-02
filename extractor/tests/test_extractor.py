from app.extractor import extract_text

def test_extract_returns_non_empty_string(sample_invoice_pdf):
    result = extract_text(sample_invoice_pdf)
    assert isinstance(result, str)
    assert len(result) > 0

def test_extract_contains_known_content(sample_invoice_pdf):
    result = extract_text(sample_invoice_pdf)
    assert "Acme Corp" in result
    assert "INV-2024-001" in result
    assert "499.00" in result

from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock

def get_test_client():
    from app.main import app
    return TestClient(app)

def test_extract_endpoint_returns_200(sample_invoice_pdf):
    client = get_test_client()
    with patch("app.main.db.save_raw_text"), \
         patch("app.main.db.get_file_path", return_value=sample_invoice_pdf):
        response = client.post("/extract", json={"job_id": 1})
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_extract_endpoint_rejects_missing_job_id():
    client = get_test_client()
    response = client.post("/extract", json={})
    assert response.status_code == 422

def test_health_endpoint():
    client = get_test_client()
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
