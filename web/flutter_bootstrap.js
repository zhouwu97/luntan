{{flutter_js}}
{{flutter_build_config}}

// CanvasKit 默认从 gstatic.com（Google CDN）下载，国内网络经常卡死导致白屏，
// 改为从应用自带 canvaskit/ 目录加载；相对路径随 <base href> 解析，本地
// flutter run 与 /forum/ 子路径部署均适用。
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
