-- 回滚到旧版 T(N)=50*N*(N-1) 阈值；游客仍保持 Lv.0。
UPDATE user_profiles AS up
SET level = CASE
        WHEN u.account_type = 'guest' THEN 0
        WHEN COALESCE(up.experience, 0) >= 2800 THEN 8
        WHEN COALESCE(up.experience, 0) >= 2100 THEN 7
        WHEN COALESCE(up.experience, 0) >= 1500 THEN 6
        WHEN COALESCE(up.experience, 0) >= 1000 THEN 5
        WHEN COALESCE(up.experience, 0) >= 600 THEN 4
        WHEN COALESCE(up.experience, 0) >= 300 THEN 3
        WHEN COALESCE(up.experience, 0) >= 100 THEN 2
        ELSE 1
    END,
    updated_at = now()
FROM users AS u
WHERE u.id = up.user_id;
