-- 回退到 000053 的审核规则；旧事件仍保留，不做破坏性清理。
CREATE OR REPLACE FUNCTION apply_forum_content_rules() RETURNS trigger AS $$
DECLARE
    account_created_at timestamptz;
    today_count integer;
    suspicious boolean;
    case_id text;
BEGIN
    SELECT created_at INTO account_created_at FROM users WHERE id = NEW.author_id;
    suspicious := NEW.content ~* '(微信群|QQ群|加微信|加 ?QQ|(^|[^0-9])[0-9]{11}([^0-9]|$))';
    SELECT count(*) INTO today_count
      FROM posts
     WHERE author_id = NEW.author_id AND created_at >= date_trunc('day', now());
    IF suspicious OR (account_created_at IS NOT NULL AND account_created_at > now() - interval '24 hours' AND today_count >= 1) THEN
        case_id := md5(random()::text || clock_timestamp()::text);
        NEW.post_status := 'pending';
        NEW.moderation_status := 'pending';
        NEW.moderation_case_id := case_id;
        INSERT INTO moderation_cases (id, target_type, target_id, source, risk_level, status)
        VALUES (case_id, 'post', NEW.id, 'auto_rule', 'medium', 'open');
        INSERT INTO risk_events (id, user_id, event_type, severity, metadata)
        VALUES (md5(random()::text || clock_timestamp()::text), NEW.author_id, 'content_auto_review', 'medium', jsonb_build_object('target_type', 'post'));
    ELSE
        NEW.post_status := COALESCE(NULLIF(NEW.post_status, ''), 'published');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION apply_comment_content_rules() RETURNS trigger AS $$
DECLARE
    account_created_at timestamptz;
    today_count integer;
    suspicious boolean;
    case_id text;
BEGIN
    SELECT created_at INTO account_created_at FROM users WHERE id = NEW.author_id;
    suspicious := NEW.content ~* '(微信群|QQ群|加微信|加 ?QQ|(^|[^0-9])[0-9]{11}([^0-9]|$))';
    SELECT count(*) INTO today_count
      FROM comments
     WHERE author_id = NEW.author_id AND created_at >= date_trunc('day', now());
    IF suspicious OR (account_created_at IS NOT NULL AND account_created_at > now() - interval '24 hours' AND today_count >= 20) THEN
        case_id := md5(random()::text || clock_timestamp()::text);
        NEW.moderation_status := 'pending';
        NEW.moderation_case_id := case_id;
        INSERT INTO moderation_cases (id, target_type, target_id, source, risk_level, status)
        VALUES (case_id, 'comment', NEW.id, 'auto_rule', 'medium', 'open');
        INSERT INTO risk_events (id, user_id, event_type, severity, metadata)
        VALUES (md5(random()::text || clock_timestamp()::text), NEW.author_id, 'content_auto_review', 'medium', jsonb_build_object('target_type', 'comment'));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
