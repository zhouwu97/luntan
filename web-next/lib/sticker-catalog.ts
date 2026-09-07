export type Sticker = { id: string; label: string };
export type StickerGroup = { id: string; name: string; items: Sticker[] };

export const stickerGroups: StickerGroup[] = [
  {
    id: "mingfeng-daily",
    name: "明风·日常",
    items: [
      ["aad70d8d064f9eb79286c1393490716c", "亲亲"], ["d0deb840abc781f414c7ad6824407964", "粘"],
      ["1c704494bbb89fce27681425cffbe6fa", "认真"], ["36286e5249dbbd659981ca530e21c047", "抱"],
      ["0eeed98ece4e89243db9dea7ccd796fd", "敢这么说话"], ["4535efdfbdc938e7c225528e8915285b", "花花"],
      ["d0ccdc6d8c3e941529e797b4d8d5ef85", "看手机"], ["5d9aa5f7f3b304bf7cffa81cdde8901c", "长条"],
      ["6d65948c4146fc8a669b9bb10f3832e6", "捏"], ["d931ab4696e4003b744092c1acd3b6c8", "拍照"],
      ["2d094a6c0e1ac32d31a65286eb141a57", "阿巴"], ["bf4fdc61f3162854bd1e8f80114f0624", "猫"],
      ["6608d1dacfcde27f87f7d3852330d0fb", "叹气"], ["986e5bd2a4b13d23b32416c046ecb068", "苦露西"],
      ["f824b5b93951ea809e59bab466114f71", "辛苦了"], ["f05144bf668463d3f2742765d6f8da14", "疑惑"],
    ].map(([id, label]) => ({ id, label })),
  },
  {
    id: "mingfeng",
    name: "明风",
    items: [
      ["693d57aca10e49cb5baf53b8dbb96c36", "探头"], ["1568a70091296e5199816f67fe457acc", "早安"],
      ["7d9614c4d56db06a13cc85420e03ffba", "晚安"], ["cee44a40131c4f95098b36430449c912", "我要闹了"],
      ["303e1f59ad80c492d2e7c15658b00870", "疑惑"], ["b62b2648f0d40805331d4c45968e4737", "OK"],
      ["b0d61e4aa42714bc2c5e5f7cf9480d98", "好耶"], ["0ccd6d087a05757fb478bf0601e8c786", "哭哭"],
      ["1c5d27144aae834d352e4f6704750458", "晕晕"], ["5ad44d700fcd9a0c81cf6834ce4e3575", "害羞"],
      ["10529d03ba8b034d0e69680e34d45af5", "摸头"], ["df6dac55ccfc89a4dfc188f320112318", "点赞"],
      ["82481e8836d11b0eac41ea5addb0da0c", "NO"], ["6159bd58fba8eb5c5254f501c958b658", "拜托了"],
      ["134dfdfb5fd355fbb504b62f0391174b", "锤"], ["9f3cfb00a3e638491e5435e5550d5c83", "惊讶"],
    ].map(([id, label]) => ({ id, label })),
  },
];

export function stickerUrl(stickerId: string): string {
  return /^[a-f0-9]{32}$/.test(stickerId) ? `/stickers/${stickerId}.png` : "";
}
