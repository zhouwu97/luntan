CREATE TABLE IF NOT EXISTS ranking_toys (
    id text PRIMARY KEY,
    rank integer NOT NULL UNIQUE,
    name text NOT NULL,
    merchant text NOT NULL DEFAULT '',
    release_year integer NOT NULL DEFAULT 2026,
    description text NOT NULL DEFAULT '',
    tags text[] NOT NULL DEFAULT ARRAY[]::text[],
    asset_key text NOT NULL DEFAULT '',
    want_count bigint NOT NULL DEFAULT 0 CHECK (want_count >= 0),
    rating_total_centi bigint NOT NULL DEFAULT 0 CHECK (rating_total_centi >= 0),
    rating_count bigint NOT NULL DEFAULT 0 CHECK (rating_count >= 0),
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ranking_toy_user_states (
    toy_id text NOT NULL REFERENCES ranking_toys(id) ON DELETE CASCADE,
    user_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wanted boolean NOT NULL DEFAULT false,
    owned boolean NOT NULL DEFAULT false,
    rating integer CHECK (rating IS NULL OR (rating >= 1 AND rating <= 10)),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (toy_id, user_id)
);

CREATE TABLE IF NOT EXISTS ranking_toy_comments (
    id text PRIMARY KEY,
    toy_id text NOT NULL REFERENCES ranking_toys(id) ON DELETE CASCADE,
    author_id text NOT NULL REFERENCES users(id),
    content text NOT NULL,
    idempotency_key text,
    like_count bigint NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS ranking_toy_comments_toy_created_idx
    ON ranking_toy_comments (toy_id, created_at DESC, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS ranking_toy_comments_author_idempotency_idx
    ON ranking_toy_comments (author_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS ranking_toy_comment_likes (
    comment_id text NOT NULL REFERENCES ranking_toy_comments(id) ON DELETE CASCADE,
    user_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (comment_id, user_id)
);

CREATE INDEX IF NOT EXISTS ranking_toy_comment_likes_user_idx
    ON ranking_toy_comment_likes (user_id, created_at DESC);

INSERT INTO ranking_toys (
    id, rank, name, merchant, release_year, description, tags, asset_key,
    want_count, rating_total_centi, rating_count
)
VALUES
    ('toy-butter-2', 1, '黄油小姐 二代', 'COC', 2025,
     '相较前作，黄油小姐2完成了一次华丽的材质蜕变。奶香味提升，肉质的软糯度提升极佳。大结构轨道带来的异物包裹感实战体验飙升。',
     ARRAY['奶香材质', '软糯包裹', '新手友好'], 'thumb_01.webp', 401, 1479, 17),
    ('toy-yingchuan-2', 2, '樱川爱 二代', 'TMT', 2026,
     '樱2软版本基本延续了前作的慢玩设定。设计结构网状结构+细密绒粒,完全属于纯新手属性的舒适按摩区，末尾方块状奇袭冲刺区也几乎拒绝一切强硬度挑战。相比琉璃子,此作才更能定义A酱最适合新手的杯子！',
     ARRAY['细密颗粒', '肉褶延续', '极致慢玩'], 'thumb_02.webp', 401, 1683, 17),
    ('toy-yutou', 3, '鱼头', 'TMT', 2025, '猎奇造型与高性价比兼顾，适合想换换口味的酱友。', ARRAY['猎奇', '高性价比', '传说神器'], 'thumb_03.webp', 497, 819, 90),
    ('toy-yuanqi', 4, '元气教练', 'TMT', 2025, '软硬适中的训练向结构，抓握反馈清晰，适合循序渐进。', ARRAY['强烈挤压', '脂软工艺', '后入抓握'], 'thumb_04.webp', 284, 558, 60),
    ('toy-shendai', 5, '神代雪乃', 'TMT', 2025, '顶级材料和一字开腿结构带来稳定的包裹感。', ARRAY['顶级材料', '一字开腿', '冷门神作'], 'thumb_05.jpg', 148, 1078, 110),
    ('toy-hoshino-2', 6, '星野爱丽丝 二代', 'TMT', 2025, '慢玩大臀与定制周边兼具，适合收藏和长期使用。', ARRAY['慢玩大臀', '定制周边', '收藏属性'], 'thumb_06.webp', 91, 400, 40),
    ('toy-nanako-2', 7, '奈奈子 二代', 'TMT', 2025, '重装包裹和柔厚肉壁的渐进式体验。', ARRAY['重装包裹', '柔厚肉壁', '渐进式'], 'thumb_07.webp', 430, 1584, 160),
    ('toy-aili', 8, '双穴爱莉', 'TMT', 2025, '双穴包裹和仿真慢玩兼顾舒适探索。', ARRAY['双穴包裹', '仿真慢玩', '舒适探索'], 'thumb_08.webp', 365, 1274, 140),
    ('toy-liulizi', 9, '水着琉璃子', 'TMT', 2025, 'A酱首选的极易入门款，软呼呼的反馈很友好。', ARRAY['A酱首选', '极易入门', '软呼呼'], 'thumb_09.webp', 241, 1275, 150),
    ('toy-kekelang', 10, '可可狼姬', 'TMT', 2025, '黑皮兽耳女仆造型，带来更明显的榨汁反馈。', ARRAY['黑皮', '榨汁强刮', '兽耳女仆'], 'thumb_10.webp', 464, 3780, 420),
    ('toy-piaogui-2', 11, '皮小鬼 二代', 'TMT', 2025, '真实回弹和肉感兼顾的毕业臀模。', ARRAY['真实回弹', '肉感', '毕业臀模'], 'thumb_11.webp', 301, 2607, 330),
    ('toy-hu-hu-zi', 12, '狐狐子', 'TMT', 2025, '一字马造型与内部铆钉带来独特触感。', ARRAY['一字马', '松鼠娘', '内部铆钉'], 'thumb_12.png', 281, 1455, 150),
    ('toy-huanru', 13, '幻乳龙娘', 'TMT', 2025, '巨乳巨臀的重型泰坦，适合偏好阻塞黏腻的人群。', ARRAY['巨乳巨臀', '重型泰坦', '阻塞黏腻'], 'thumb_13.webp', 186, 1034, 110),
    ('toy-xiaogui', 14, '小鬼魔皇', 'TMT', 2025, '高刺榨汁和水波肉臀，强度更明显。', ARRAY['高刺榨汁', '重型机甲', '水波肉臀'], 'thumb_14.webp', 297, 2070, 230),
    ('toy-chiyuan', 15, '赤鸢', 'TMT', 2025, '爆乳脂软与机械横纹的组合，包裹感稳定。', ARRAY['爆乳脂软', '大臀', '机械横纹'], 'thumb_15.webp', 36, 460, 50),
    ('toy-tun-niang', 16, '五宫豚娘物语', 'TMT', 2025, '猎奇福瑞向设计，海豚仿生结构有辨识度。', ARRAY['猎奇狂', '福瑞控', '海豚仿生'], 'thumb_16.webp', 145, 869, 110),
    ('toy-baishi-2', 17, '白丝壁女 二代', 'TMT', 2025, '重力负压与暴力内腔的加硬体验。', ARRAY['重力负压', '暴力内腔', '加硬'], 'thumb_17.webp', 91, 413, 70),
    ('toy-gonglai', 18, '宫濑 Soft', 'TMT', 2025, '脂软材质与细密包裹，适合超软慢玩。', ARRAY['脂软材质', '细密包裹', '超软慢玩'], 'thumb_18.webp', 426, 2262, 260),
    ('toy-qianmei', 19, '千美', 'TMT', 2025, '直筒型和极致肉厚带来被动包裹。', ARRAY['直筒型', '极致肉厚', '被动包裹'], 'thumb_19.webp', 61, 450, 50),
    ('toy-shuiye-2', 20, '水野 2', 'TMT', 2025, '体脂水感的温和型设计，顺滑贴合。', ARRAY['体脂水感', '温和型', '顺滑贴合'], 'thumb_20.webp', 429, 455, 50)
ON CONFLICT (id) DO UPDATE SET
    rank = EXCLUDED.rank,
    name = EXCLUDED.name,
    merchant = EXCLUDED.merchant,
    release_year = EXCLUDED.release_year,
    description = EXCLUDED.description,
    tags = EXCLUDED.tags,
    asset_key = EXCLUDED.asset_key,
    updated_at = now();

INSERT INTO users (id, username, status)
VALUES
    ('ranking-reviewer-1', 'ranking_reviewer_1', 'active'),
    ('ranking-reviewer-2', 'ranking_reviewer_2', 'active')
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_profiles (user_id, nickname, level)
VALUES
    ('ranking-reviewer-1', '菜菜M', 3),
    ('ranking-reviewer-2', '杂鱼萌萌', 3)
ON CONFLICT (user_id) DO UPDATE SET nickname = EXCLUDED.nickname, level = EXCLUDED.level, updated_at = now();

INSERT INTO ranking_toy_comments (id, toy_id, author_id, content, like_count)
VALUES
    ('toy-comment-yingchuan-1', 'toy-yingchuan-2', 'ranking-reviewer-1', 'A酱的慢玩断折作，比琉璃子好比琉璃子贵就是没有琉璃子陪伴的回忆而已（悲…）', 8),
    ('toy-comment-yingchuan-2', 'toy-yingchuan-2', 'ranking-reviewer-2', '这个盒子的好用一点，比较软，锻炼和练射时长选这个版本就行了。礼盒版是周边多，配送点东西，但是胶体是一样的。', 3)
ON CONFLICT (id) DO UPDATE SET content = EXCLUDED.content, like_count = EXCLUDED.like_count, updated_at = now();

INSERT INTO ranking_toy_comments (id, toy_id, author_id, content, like_count)
SELECT 'toy-comment-' || t.id, t.id, 'ranking-reviewer-2', '实际体验记录已同步到服务器，欢迎酱友补充自己的感受。', 1
FROM ranking_toys t
WHERE t.id <> 'toy-yingchuan-2'
ON CONFLICT (id) DO NOTHING;
