# 卡尺源图细化与加载

2026-11-03，使用内置 imagegen 编辑原始 frame2_caliper.jpg；源图保留，新图为 frame2_caliper_refined.png。

处理了阴影、背景纹理与细碎杂点，强化上下刻度的连续实线和数字，提亮并加粗左侧 mm/inch、OFF、ON、ZERO，以及右侧 DL90150B、0-150mm、ELECTRONIC DIGITAL CALIPER。LCD 保持空白。AI 会重绘局部字体和刻度，此图用于演示，不作为计量基准。

## 生成及加载

在 E:\FPGA2026\Ti60f225_sc431hai2hdmi_v6_edge 目录运行：

```powershell
python tools/gen_demo_raw.py --img1 demo_images/frame1_screw_shadowfree.png --cx1 817 --img2 demo_images/frame2_caliper_refined.png --out demo_raw_refined
```

输出 demo_raw_refined/frame1.raw 和 frame2.raw，每帧 2,073,600 字节。第一帧与此前优化螺丝逐字节相同；第二帧为新版卡尺，SHA256：772440872146c8155b1b45093fb4f09e3cc376adea68bf9ab2fa4057ab6f1672。

关闭 Programmer，运行原来的入口：

```powershell
.\load_demo_shadowfree.ps1
```

入口已更新为同时选用 demo_raw_refined 两帧。板子继续使用 outflow_demo_fix/ti60f225_oob.bit，无需重新编译或下载比特流。

原版卡尺对照命令：

```powershell
python tools/jtag_load_demo.py --raw1 demo_raw_shadowfree/frame1.raw --raw2 demo_raw/frame2.raw
```

## 检查

上屏预览：demo_raw_refined/frame2_preview.png。
软件边缘对照：demo_raw_refined/caliper_canny_comparison.png。

软件对照按实际 960 像素宽度，使用 3×3 高斯、Canny 低阈值 60 / 高阈值 120、L1 梯度。新版能提取连续刻度及左右文字；软件结果不等于板端结果，实际去马赛克与边缘连接存在差异，小字仍受显示采样分辨率限制。

## 最终提示词（内置 imagegen）

Use case: precise-object-edit. Edit the provided ORIGINAL digital caliper photo as a high-fidelity image for a hardware Canny edge-detection demonstration. Keep the same single physical digital caliper, its exact horizontal orientation, jaw geometry and left placement, slider position, blank LCD, black plastic body, yellow ruler insert, and long right tail, with the same landscape aspect ratio and composition. Preserve all real labels and measurement markings, never add a reading to the blank LCD.
Primary goal: clean shadow-free product photograph whose real graduation lines and lettering remain clear when the full image is reduced to just 960 pixels wide. Replace the entire textured gray tabletop, hairs, dust and ALL cast/contact shadows around and below the caliper with an absolutely smooth uniform light gray (RGB about 238,238,238). Remove speckle and glare from the ruler surface and black housing; diffuse even lighting throughout. Keep the housing smooth near-black with gentle broad shading, and the ruler strip smooth pale lemon yellow without texture or hot spots. Keep crisp realistic solid outer edges without artificial outlines.
VERY IMPORTANT tiny details: faithfully restore the existing vertical graduation strokes as straight clean solid near-black evenly spaced strokes, all attached to their correct top/bottom baselines, maintaining minor/major tick lengths and positions. At the final 960-wide display, each minor stroke should be about 1.5 to 2 pixels thick with visible light gaps, never merged, fuzzy or dotted. Preserve the metric labels in left-to-right order exactly: "70 80 90 100 110 120 130 140 150" along the lower scale, "mm" at the right; preserve the upper scale labels "3 4 5 6" and "in" with their proper graduations. Use clean bold dark typography on the light ruler strip with distinguishable letter counters. Do not clutter with duplicate markings or invent missing measurement values.
Restore the LEFT housing labels in clean bright neutral near-white, high contrast against smooth black: "mm/inch" above the blank LCD next to the blue button, and "OFF" "ON" "ZERO" below the LCD with their existing red and pale-yellow buttons in the original positions. Make lettering slightly bolder and more legible rather than adding a stroke around it. Preserve the blank light gray-green LCD and its thin bright frame.
Restore the RIGHT black tail labels verbatim in crisp high-contrast bright neutral ivory/white so grayscale edge detection can see them: main line "DL90150B   0-150mm", smaller line "ELECTRONIC DIGITAL CALIPER". Make efficient use of the existing right black label area; main text should be about 16-18 pixels high and subtitle 11-12 pixels high after downscaling the whole image to 960 pixels wide, with clean roughly 2-pixel letter strokes and open counters. It is acceptable to modestly enlarge/bolden the original printing within its original areas to support readability, but do not move labels to other parts of the image.
Photorealistic retouched product image with tidy readable ink printing, precise regular lines and clear jaws, no noise texture. No red outlines, no edge-map, no annotations outside the product, no watermark, no extra objects, no ruler reconstruction into another model. No shadow whatsoever.

