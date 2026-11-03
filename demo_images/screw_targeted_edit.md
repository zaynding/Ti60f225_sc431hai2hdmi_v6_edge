# 螺丝三处针对性优化

使用内置 imagegen，以 frame1_screw_natural.png（第二版）为基准：
1. 减少右侧帽面的细碎反光、麻点与划痕，保留宽缓金属反射。
2. 增强帽子右下轮廓、底部圆弧及邻近下侧螺纹的局部对比。
3. 减轻左下方投影的突变，保留贴近物体的少量接触阴影。

输出源图：demo_images/frame1_screw_targeted.png。
输出 RAW：demo_raw_screw_targeted/frame1.raw，2,073,600 字节。
SHA256：1d5447f8d3a7d0e391472c3430bc21f299c7f73b42b6690af7d02700746e773b。

## 加载

```powershell
cd "E:\FPGA2026\Ti60f225_sc431hai2hdmi_v6_edge"
.\load_demo_natural.ps1
```

两个入口 load_demo_natural.ps1 / load_demo_shadowfree.ps1 现在均选择新版螺丝 RAW 和第二版卡尺 demo_raw_natural/frame2.raw。不改 FPGA RTL 或比特流，不影响 K3 清除缓存 3/4 功能。

生成命令：

```powershell
python tools/gen_demo_raw.py --img1 demo_images/frame1_screw_targeted.png --cx1 817 --img2 demo_images/frame2_caliper_natural.png --out demo_raw_screw_targeted
```

第二帧已与 demo_raw_natural/frame2.raw 做逐字节比较，完全一致。

## 验证与限制

预览与软件边缘对照：demo_raw_screw_targeted/targeted_canny_check.png。
按 960 像素面板宽度、3×3 高斯、Canny 低阈值 80 / 高阈值 160、L1 梯度检查（对应照片中手动第 3/6 档高阈值 160）：

- 帽面内部固定采样区域边缘像素：1114 → 162。
- 右下轮廓固定采样区域边缘像素：10 → 56。
- 左下背景采样区两版均无软件边缘，因此不能据此量化板端投影误检的改善。
- 卡尺 RAW 逐字节保持不变。

这些计数只描述固定区域的软件近似，不是板端准确率，也不能把边缘像素增加直接视为检测率提高。实际 FPGA 拜耳重建、NMS 和连接与 OpenCV 不同，需要上板检查。
AI 按局部目标修图仍会改变目标以外的微小纹理；中段螺纹采样区平均绝对像素差为 10.284 / 255，未宣称非目标区域像素完全不变。避免把生成修图当作仅改变背景的确定性处理，也不作为计量基准。

## 最终提示词（内置 imagegen）

Use case: precise-object-edit, localized photographic retouch for a 960-pixel-wide FPGA Canny edge detection demo. The supplied photograph is the current baseline. This is NOT a request to relight or regenerate the whole image. Preserve the current gray tabletop, natural photographic appearance, composition, canvas dimensions/aspect ratio, exact screw geometry, placement, size, all thread pitch/count, and the already good upper/central/left threaded surfaces. Change only these three local areas, feathering transitions:
1. RIGHT HEAD/FLANGE: in the narrow vertical metal head near x=1080..1140, y=310..595 on the 1672x941 image, suppress tiny pits, scratches, peppery bright spots and small high-frequency specular reflections INSIDE the flange. Keep a natural broad metallic reflection and cylindrical shading, but make the flat/curved face smooth enough to avoid speckled Canny edges. Keep its true outer contour SHARP and unchanged, including top curve. No mirror chrome, plastic look, drawn rim or halo.
2. LOWER-RIGHT REAL OBJECT EDGES: the lower end/rounded bottom and right side of that flange near x=1080..1145,y=480..595, and the last few lower thread teeth just to its left near x=940..1090,y=485..545, currently merge tonally into the gray background and are missed. Restore a clean, focused natural object-background transition by locally making the metal edge moderately darker while retaining subtle metal shading, and letting the immediate tabletop outside be slightly lighter. Make the existing bottom curvature and lower-right outline continuous and high local contrast after downscaling to 960px panel width. Sharpen ONLY this physical perimeter and existing lower-right teeth, not internal scratches. No added black outline, stroke, glow, fake ridge or changed silhouette.
3. LOWER-LEFT CAST SHADOW: outside the screw below the left third of the shaft near x=490..760,y=535..620, lift and diffuse the unwanted dark shadow edge into the tabletop, reducing that shadow contrast by about half. Keep a very narrow natural contact shadow immediately touching the object, but remove the detached narrow dark/sharp band below the tip that would be mistaken for a second contour. Feather broadly, retain the gray tabletop tone and fine natural surface elsewhere. Do not erase or blur any of the actual lower-left thread teeth or outline.
Keep everything outside those local areas unchanged to the greatest possible extent. Do NOT apply global sharpening, global denoising, overall color/brightness/contrast changes, object redraw, a new background, or a larger/darker shadow. Natural real metal photographic detail must remain across the shaft. No text, no diagrams, no colored outlines, no watermark.

