import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock

@pytest.fixture
def client():
    from app.main import app
    return TestClient(app, follow_redirects=False)

def test_login_page_loads(client):
    response = client.get("/login")
    assert response.status_code == 200

def test_login_valid_email_sets_cookie(client):
    response = client.post("/login", data={"email": "test@example.com", "password": "anything"})
    assert response.status_code == 302
    assert "user_email" in response.cookies

def test_login_invalid_email_rejected(client):
    response = client.post("/login", data={"email": "notanemail", "password": "anything"})
    assert response.status_code == 200
    assert b"valid email" in response.content.lower()

def test_upload_page_requires_login(client):
    response = client.get("/upload")
    assert response.status_code == 302
    assert "/login" in response.headers["location"]

def test_results_page_requires_login(client):
    response = client.get("/results/1")
    assert response.status_code == 302
    assert "/login" in response.headers["location"]

def test_process_endpoint_calls_extractor_and_parser(client):
    with patch("app.main.httpx.post") as mock_post, \
         patch("app.main.db.get_job", return_value={"file_path": "/tmp/f.pdf"}):
        mock_post.return_value = MagicMock(status_code=200)
        response = client.post("/process/1")
    assert response.status_code == 200
    assert mock_post.call_count == 2
