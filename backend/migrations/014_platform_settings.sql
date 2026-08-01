-- Singleton platform settings row — branding/contact/SMTP config the Admin Settings screen
-- can edit. Deliberately does NOT include a live payment-gateway-keys field (there is no
-- active payment gateway on this platform — payments are self-declared UPI) or a
-- commission%/escrow-days override (those stay env-configured; see config.go) to avoid
-- silently diverging from the values orders/escrow actually compute with.
CREATE TABLE platform_settings (
    id              INT PRIMARY KEY DEFAULT 1,
    app_name        VARCHAR(150) NOT NULL DEFAULT 'One Bharat Export Import',
    logo_url        TEXT,
    support_email   VARCHAR(255),
    currency        VARCHAR(10) NOT NULL DEFAULT 'INR',
    smtp_host       VARCHAR(255),
    smtp_port       INT,
    smtp_username   VARCHAR(255),
    smtp_password   TEXT,
    smtp_from       VARCHAR(255),
    updated_by      UUID REFERENCES users(id),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT single_row CHECK (id = 1)
);

INSERT INTO platform_settings (id) VALUES (1);
