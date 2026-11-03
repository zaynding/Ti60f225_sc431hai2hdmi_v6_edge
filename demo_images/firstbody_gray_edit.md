# 第一版主体基准 + 灰背景柔影

使用内置 imagegen，以最初去阴影强化版为编辑输入，而不是第二版：
- 螺丝输入：demo_images/frame1_screw_shadowfree.png。
- 卡尺输入：demo_images/frame2_caliper_refined.png。

最终源图：
- demo_images/frame1_screw_firstbody_gray.png。
- demo_images/frame2_caliper_firstbody_gray.png。

目标是保留第一版的螺纹、金属反光、刻度、字形、线宽与构图，仅调整外围灰色桌面及柔和阴影。生成式编辑不等于像素锁定，不能保证主体每个像素不变；对照图保留了第一版与新图，便于检查。没有把第二版素材作为输入。

## 生成及加载

```powershell
python tools/gen_demo_raw.py --img1 demo_images/frame1_screw_firstbody_gray.png --cx1 817 --img2 demo_images/frame2_caliper_firstbody_gray.png --out demo_raw_firstbody_gray
.\load_demo_natural.ps1
```

在 E:\FPGA2026\Ti60f225_sc431hai2hdmi_v6_edge 工程目录运行。旧入口 load_demo_shadowfree.ps1 同样指向本版。两个 RAW 位于 demo_raw_firstbody_gray，每个 2,073,600 字节，校验值在 quality_metrics.json 中。覆盖缓存 1/2，无需重编或重烧，不改 K3 清除缓存 3/4 功能。

## 检查

demo_raw_firstbody_gray/firstbody_canny_check.png 包含第一版、新版以及实际 960 像素宽度的软件 Canny（低阈值 80 / 高阈值 160、3×3 高斯、L1 梯度）。软件结果仅作对照，不等于 FPGA 去马赛克、NMS 和边缘连接的实际输出。帽子右侧轮廓仍有局部断点，不能声称所有漏检均已消除，需要上板确认。

如需完全恢复第一版的原始 RAW，而不保留新灰背景，可显式运行：
```powershell
python tools/jtag_load_demo.py --raw1 demo_raw_refined/frame1.raw --raw2 demo_raw_refined/frame2.raw
```

## 最终提示词（内置 imagegen）

Use case: precise-object-edit / background replacement only. The supplied image is the FIRST enhanced version. Its object is the authoritative edit target and must be preserved, NOT redrawn or relit. The user's crucial correction is: both the screw's internal threads/reflections and the caliper's internal markings/text must remain as in the FIRST version, not the later natural/re-rendered version. Treat the entire object and every interior pixel as a protected foreground mask. Make edits only to the tabletop OUTSIDE the exact existing silhouette, keeping its existing antialiased outline sharp. Do not change the object material, brightness, contrast, color, printed font weight, scale line width, geometry, position, size or viewpoint; do not add any surface detail or noise. Preserve every existing graduation, label, number, reflection and thread exactly as supplied. In particular do not thin, soften or reinterpret any ruler strokes or small text, and do not reintroduce scratches/glitter to the smooth screw head. Do not change or globally sharpen the foreground.
Replace ONLY the near-white empty tabletop/background with a moderately dull warm-neutral gray matte tabletop, average gray level about 170-180, with very subtle broad natural illumination variation, no distracting dust or high-contrast grain. Add a restrained photorealistic soft cast shadow beneath and slightly right of the object, as if it rests on this gray surface. Keep the shadow diffuse, about 8-14 gray levels below its neighboring tabletop, feathered over a wide transition so it doesn't form a hard extra Canny contour. For the screw, keep the bottom-left shadow especially light and smooth, retain high tonal contrast around the lower-right head's existing sharp perimeter, and never darken the tabletop into that outline. For the caliper, a soft modest shadow follows the jaws, slider and ruler beam without a hard rectangular border. Do not turn this into a CGI redraw: only replace the outside tabletop and add a light soft shadow. Maintain original canvas aspect ratio, object location and photographic framing. No white background, no fake outlining, no halo, no text outside the object, no watermark. Return the same first-version object intact against the new gray tabletop.

