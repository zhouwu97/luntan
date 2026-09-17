import { test, expect } from "@playwright/test";
import { parseContentWithLinks } from "../components/link-text";

test.describe("parseContentWithLinks", () => {
  test("correctly parses URL directly followed by Chinese characters", () => {
    const text = "https://galgamex.com/这里面有挺多来着";
    const segments = parseContentWithLinks(text);

    expect(segments).toEqual([
      {
        type: "link",
        content: "https://galgamex.com/",
        href: "https://galgamex.com/",
      },
      {
        type: "text",
        content: "这里面有挺多来着",
      },
    ]);
  });

  test("correctly parses www links and trims trailing punctuation", () => {
    const text = "访问 (www.example.com/test?a=1). 看看吧！";
    const segments = parseContentWithLinks(text);

    expect(segments).toEqual([
      {
        type: "text",
        content: "访问 (",
      },
      {
        type: "link",
        content: "www.example.com/test?a=1",
        href: "https://www.example.com/test?a=1",
      },
      {
        type: "text",
        content: "). 看看吧！",
      },
    ]);
  });

  test("handles plain text without URLs", () => {
    const text = "这是一条没有网址的普通评论。";
    const segments = parseContentWithLinks(text);

    expect(segments).toEqual([
      {
        type: "text",
        content: text,
      },
    ]);
  });
});
