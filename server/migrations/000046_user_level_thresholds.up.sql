-- 全站等级阈值与 SYLUlive MCP 分支保持一致：
-- Lv.1=0、Lv.2=50、Lv.3=150、Lv.4=500、Lv.5=1000、
-- Lv.6=2500、Lv.7=5000、Lv.8=8000。
-- 游客继续累计经验，但展示等级永久固定为 Lv.0。
UPDATE user_profiles AS up
SET level = CASE
        WHEN u.account_type = 'guest' THEN 0
        WHEN COALESCE(up.experience, 0) >= 8000 THEN 8
        WHEN COALESCE(up.experience, 0) >= 5000 THEN 7
        WHEN COALESCE(up.experience, 0) >= 2500 THEN 6
        WHEN COALESCE(up.experience, 0) >= 1000 THEN 5
        WHEN COALESCE(up.experience, 0) >= 500 THEN 4
        WHEN COALESCE(up.experience, 0) >= 150 THEN 3
        WHEN COALESCE(up.experience, 0) >= 50 THEN 2
        ELSE 1
    END,
    updated_at = now()
FROM users AS u
WHERE u.id = up.user_id;
