# 参考与素材说明

以下项目用于研究实现方式。本项目未复制其源代码，也不需要安装或运行它们。

| 参考项目 | 参考范围 |
| --- | --- |
| [Tangc/codex-skin-launcher](https://github.com/Tangc/codex-skin-launcher) | macOS 原生窗口、应用标识与独立启动入口 |
| [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) | 整窗壁纸、透明表面、本机 CDP 接入及目标进程校验 |
| [NativeDog1/dsh-boot-animation](https://github.com/NativeDog1/dsh-boot-animation) | 可跳过的覆盖式片头、完成后移除、素材就绪后播放和超时兜底 |

DSH 使用自己的覆盖层接口，不能直接安装到 Codex。本项目的动画和外部接入独立实现，不引入视频片库或第三方运行时依赖，也不使用持续监控进程。

## 视觉素材

- 默认头像和背景来自项目所有者提供的本地图片，经过确定性的缩放与居中裁切。
- `assets/contours.js` 从运行用背景通过 macOS Vision 提取。自定义背景在导入时由本机 Canvas 生成轮廓。
- 粉色启动图标基于官方花形标志进行颜色编辑，仅用于区分个人启动入口。原标志的权利归相应权利人。
- 早期原型曾用参考视频的截图和 ImageGen 重建头像及背景；这些备用图片、截图与视频不在本次提交范围内。
- 动画本身由 HTML、CSS、Canvas 和 SVG 绘制，无音轨、远程字体、CDN 或在线图片请求。

动画从头像碎片过渡到背景的散线，再从左到右汇聚，最后显现彩色图。人物素材、品牌标志和项目代码的权利应分别看待；未对第三方素材授予任何额外许可。
