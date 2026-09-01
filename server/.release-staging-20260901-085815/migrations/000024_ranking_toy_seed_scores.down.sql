UPDATE ranking_toys
SET rating_total_centi = CASE id
    WHEN 'toy-butter-2' THEN 14790
    WHEN 'toy-yingchuan-2' THEN 16830
    WHEN 'toy-yutou' THEN 8190
    WHEN 'toy-yuanqi' THEN 5580
    WHEN 'toy-shendai' THEN 10780
    WHEN 'toy-hoshino-2' THEN 4000
    WHEN 'toy-nanako-2' THEN 15840
    WHEN 'toy-aili' THEN 12740
    WHEN 'toy-liulizi' THEN 12750
    WHEN 'toy-kekelang' THEN 37800
    WHEN 'toy-piaogui-2' THEN 26070
    WHEN 'toy-hu-hu-zi' THEN 14550
    WHEN 'toy-huanru' THEN 10340
    WHEN 'toy-xiaogui' THEN 20700
    WHEN 'toy-chiyuan' THEN 4600
    WHEN 'toy-tun-niang' THEN 8690
    WHEN 'toy-baishi-2' THEN 4130
    WHEN 'toy-gonglai' THEN 22620
    WHEN 'toy-qianmei' THEN 4500
    WHEN 'toy-shuiye-2' THEN 4550
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
