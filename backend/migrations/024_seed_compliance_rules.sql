-- Journey 6: compliance_rules was created empty in 016_compliance_center.sql with no seed
-- data, so ComplianceService.GenerateChecklist always matched zero rules and
-- IsShipmentBlocked always reported "not blocked" — compliance never actually gated
-- anything until an admin manually added rules. Seeds the baseline set of mandatory
-- documents every international trade order needs, wildcarded (NULL) on
-- origin/destination/hs_code/shipping_mode so they apply to every order regardless of lane —
-- admins can still add lane-specific rules on top via the existing CreateRule endpoint.
INSERT INTO compliance_rules (document_name, responsible_role, mandatory, display_order, description) VALUES
    ('Commercial Invoice', 'exporter', true, 10, 'Itemized invoice showing goods, value, and terms of sale.'),
    ('Packing List', 'exporter', true, 20, 'Itemized packing details (weights, dimensions, package count) matching the invoice.'),
    ('Certificate of Origin', 'exporter', true, 30, 'Certifies the country in which the goods were manufactured.'),
    ('Export Declaration', 'exporter', true, 40, 'Customs declaration filed by the exporter''s country before goods leave.'),
    ('Import Declaration', 'importer', true, 50, 'Customs declaration filed by the importer''s country on arrival.'),
    ('Insurance Certificate', 'importer', false, 60, 'Proof of cargo insurance coverage for the shipment.');
