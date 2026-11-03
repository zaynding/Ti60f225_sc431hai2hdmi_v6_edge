# 螺丝源图去阴影版本

日期：2026-11-03。使用内置 imagegen 编辑原始 `frame1_screw.jpg`，保留原文件。

- 编辑图：`frame1_screw_shadowfree.png`，1672 × 941。
- 目标：去掉投影和桌面杂点，平滑细碎反光，改善螺纹下缘与背景的分离。
- AI 修图会重建部分表面细节；这是演示用图，轮廓和尺寸不作为测量基准。
- 原图、原始 `demo_raw` 和 FPGA 算法保持原样。新 RAW 放在 `demo_raw_shadowfree`。

## 生成板载数据

从工程目录执行：

```powershell
python tools/gen_demo_raw.py --img1 demo_images/frame1_screw_shadowfree.png --cx1 817 --out demo_raw_shadowfree
```

中心列 817 是按新图宽度等比例换算原来的取景中心 900；使用原有裁剪、白平衡预补偿、拜耳排列与 16 字节反序流程。

`demo_raw_shadowfree/frame1.raw` 为 2,073,600 字节，SHA256：`1251a4ddfe41e53961d96723eba79604a184bd23508136394a6f26c802dcd924`。
`frame1_preview.png` 为 960 × 1080 的显示窗口预览。此目录的第二帧与原 `demo_raw/frame2.raw` 逐字节一致。

## 上板查看

使用已经修复第二槽位地址的 `outflow_demo_fix/ti60f225_oob.bit`。如果板子正在运行这个版本，不必再次下载比特流。关闭占用 JTAG 的 Programmer 后，从工程目录执行：

```powershell
.\load_demo_shadowfree.ps1
```

也可以使用当前 Python：

```powershell
python tools/jtag_load_demo.py --raw1 demo_raw_shadowfree/frame1.raw
```

后续卡尺优化已接入 `load_demo_shadowfree.ps1`，现在该入口加载优化螺丝及优化卡尺（`demo_raw_refined`）；上面的 Python 命令仍加载优化螺丝及原版卡尺，可作对照。运行原来的 `load_demo.ps1` 可重新加载两张原图。卡尺说明见 `frame2_caliper_refined_edit.md`。
实际 Canny 显示效果仍需上板观察。

检查结果：RAW 尺寸、第二帧保持一致、加载入口选择新版 RAW 及 JTAG 数据打包均已核验（使用 `--emit-test`，未连接 USB）。对预览中物体上方及下方的背景抽样区域，用软件 OpenCV 3×3 高斯及 Canny（低阈值 60、高阈值 120、L1 梯度）作辅助检查，杂散边缘像素从 101 降至 0，背景灰度标准差从 11.134 降至 0.572，见 `demo_raw_shadowfree/quality_metrics.json`。这个结果只描述抽样区域的软件检查，不是 FPGA 全图结果。

## 编辑提示词（内置 imagegen）

Use case: lighting-weather / precise-object-edit. Edit ONLY the provided original screw photograph, an FPGA edge-detection demo source image, not a screenshot. Preserve the exact same single metal screw/bolt, same horizontal pose (threaded tip on the left, wide thin flange/head seen edge-on on the right), same viewpoint, placement, scale, silhouette, head thickness and existing thread spacing/count, with generous blank space above and below as in the original landscape composition. Keep the original approximately 1842:1036 canvas ratio and the screw's original position within it. Primary request: remove the entire cast shadow below the screw, including the long dark horizontal band and the vertical shadow below the right head; replace the textured tabletop and every speck/scratch/hair with a perfectly uniform seamless very light neutral gray background (approximately RGB 238,238,238), including between the lower thread teeth and underneath the head. There should be NO cast shadow, NO contact-shadow strip, NO ground line, NO background gradient or visible texture anywhere. Relight the actual screw with broad diffuse studio light and gentle upward fill: recover the lower thread valleys and lower silhouette so each existing thread tooth separates crisply from the bright background, while preserving realistic metallic volume. Reduce tiny reflective speckles, scratches and harsh blown highlights that would create false Canny edges, use smooth mid-gray metal with controlled broad highlights and clear clean thread grooves. The lower outer contour must be sharply focused and continuous, equal in clarity to the upper contour, using true local tonal separation rather than a drawn stroke. Retouch with high fidelity, do not invent extra teeth or reshape the head, do not change the angle or crop/zoom/recenter. Photorealistic clean product photograph. No text, no labels, no color outlines, no edge-map, no black rim, no halo, no diagram, no watermark, no extra objects.
