ALTER TABLE email_codes
DROP CONSTRAINT IF EXISTS email_codes_purpose_check;

ALTER TABLE email_codes
ADD CONSTRAINT email_codes_purpose_check
CHECK (
    purpose IN (
        'login',
        'register',
        'password_reset'
    )
);
