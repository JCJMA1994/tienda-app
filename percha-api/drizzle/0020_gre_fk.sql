ALTER TABLE einvoice_documents ADD CONSTRAINT einvoice_documents_transfer_fk FOREIGN KEY (tenant_id, transfer_id) REFERENCES transfers (tenant_id, id);
