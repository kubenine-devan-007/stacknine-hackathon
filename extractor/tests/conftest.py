import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pytest
from fpdf import FPDF

@pytest.fixture(scope="session")
def sample_invoice_pdf(tmp_path_factory):
    path = str(tmp_path_factory.mktemp("invoices") / "invoice.pdf")
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", size=12)
    for line in [
        "Acme Corp",
        "From: Acme Corp",
        "Invoice #INV-2024-001",
        "Date: 2024-03-15",
        "",
        "Web Hosting          299.00",
        "Support Plan         150.00",
        "Setup Fee             50.00",
        "",
        "TOTAL: 499.00",
    ]:
        pdf.cell(0, 10, line, new_x="LMARGIN", new_y="NEXT")
    pdf.output(path)
    return path
