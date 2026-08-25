-- 统一榜单种子数据的汇总口径：评分总和按 centi（评分 * 100）保存。
UPDATE ranking_toys
SET rating_total_centi = CASE id
    WHEN 'toy-butter-2' THEN 14790
    WHEN 'toy-yingchuan-2' THEN 16830
    WHEN 'toy-yutou' THEN 81900
    WHEN 'toy-yuanqi' THEN 55800
    WHEN 'toy-shendai' THEN 107800
    WHEN 'toy-hoshino-2' THEN 40000
    WHEN 'toy-nanako-2' THEN 158400
    WHEN 'toy-aili' THEN 127400
    WHEN 'toy-liulizi' THEN 127500
    WHEN 'toy-kekelang' THEN 378000
    WHEN 'toy-piaogui-2' THEN 260700
    WHEN 'toy-hu-hu-zi' THEN 145500
    WHEN 'toy-huanru' THEN 103400
    WHEN 'toy-xiaogui' THEN 207000
    WHEN 'toy-chiyuan' THEN 46000
    WHEN 'toy-tun-niang' THEN 86900
    WHEN 'toy-baishi-2' THEN 41300
    WHEN 'toy-gonglai' THEN 226200
    WHEN 'toy-qianmei' THEN 45000
    WHEN 'toy-shuiye-2' THEN 45500
    ELSE rating_total_centi
END,
updated_at = now()
WHERE id IN (
    'toy-butter-2', 'toy-yingchuan-2', 'toy-yutou', 'toy-yuanqi',
    'toy-shendai', 'toy-hoshino-2', 'toy-nanako-2', 'toy-aili',
    'toy-liulizi', 'toy-kekelang', 'toy-piaogui-2', 'toy-hu-hu-zi',
    'toy-huanru', 'toy-xiaogui', 'toy-chiyuan', 'toy-tun-niang',
    'toy-baishi-2', 'toy-gonglai', 'toy-qianmei', 'toy-shuiye-2'
);
