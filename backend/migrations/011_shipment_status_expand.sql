-- Expands shipment_status with the granular in-transit stages the logistics workflow
-- needs (pickup scheduling, warehouse, customs, loaded, arrived, out-for-delivery).
-- Purely additive — existing values (pending/assigned/picked_up/in_transit/delivered/
-- exception) are untouched, so every existing row and code path keeps working exactly
-- as before; new values are only used by NEW status transitions going forward.
ALTER TYPE shipment_status ADD VALUE IF NOT EXISTS 'pickup_scheduled' AFTER 'assigned';
ALTER TYPE shipment_status ADD VALUE IF NOT EXISTS 'at_warehouse' AFTER 'picked_up';
ALTER TYPE shipment_status ADD VALUE IF NOT EXISTS 'customs_clearance' AFTER 'at_warehouse';
ALTER TYPE shipment_status ADD VALUE IF NOT EXISTS 'loaded' AFTER 'customs_clearance';
ALTER TYPE shipment_status ADD VALUE IF NOT EXISTS 'arrived_at_destination' AFTER 'in_transit';
ALTER TYPE shipment_status ADD VALUE IF NOT EXISTS 'out_for_delivery' AFTER 'arrived_at_destination';
