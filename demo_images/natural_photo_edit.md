# 自然灰背景、柔和投影版（v3）

当前默认加载入口已回退到“第二版”：`frame1_screw_natural.png`、`frame2_caliper_natural.png`，RAW 位于 `demo_raw_natural`。这是最初的灰背景、较浅柔影版本，未进行后续加深或扩大阴影。`load_demo_natural.ps1` 和 `load_demo_shadowfree.ps1` 均加载此版。下文保留 v3 的生成记录；K3 清除缓存 3、4 的 RTL 和比特流不受图片回退影响。

2026-11-03，使用内置 imagegen 编辑原始螺丝和卡尺照片，随后按用户反馈稍微加深并扩大阴影。原图、此前去阴影版、自然版 v1/v2 均保留。

最终源图：
- demo_images/frame1_screw_natural_v3.png
- demo_images/frame2_caliper_natural_v3.png

保持偏暗、哑光、略有实拍纹理的暖灰桌面，保留金属反光和塑料质感；阴影方向仿照原图，但减弱硬边。v2 略加深，v3 保持深浅并向下、向右适当扩大柔和投影范围。允许少量投影边缘被提取，以保留真实感。AI 编辑会重建局部纹理，不作为计量基准。

## 生成与加载

从工程目录执行：

```powershell
python tools/gen_demo_raw.py --img1 demo_images/frame1_screw_natural_v3.png --cx1 817 --img2 demo_images/frame2_caliper_natural_v3.png --out demo_raw_natural_v3
```

两个 RAW 各 2,073,600 字节；尺寸与校验值记录在 demo_raw_natural_v3/quality_metrics.json。预览文件为同目录 frame1_preview.png、frame2_preview.png。

关闭 Programmer，在 PowerShell 执行：

```powershell
cd "E:\FPGA2026\Ti60f225_sc431hai2hdmi_v6_edge"
.\load_demo_natural.ps1
```

目前上述两个加载入口均指向第二版（demo_raw_natural），覆盖缓存帧 1、2；缓存 3、4 不变。沿用正在运行的比特流即可，无需重新编译、烧录或清空缓存。

回到上一版完全去阴影图，可显式指定：

```powershell
python tools/jtag_load_demo.py --raw1 demo_raw_refined/frame1.raw --raw2 demo_raw_refined/frame2.raw
```

## 验证范围

已检查两张源图、实际 960 像素宽度预览及 RAW 文件长度。自然版软件检查图为 demo_raw_natural_v3/natural_canny_check.png，采用 3×3 高斯和 Canny 低阈值 60 / 高阈值 120、L1 梯度；主要轮廓、螺纹、刻度及文字可以提取，未出现明显脱离物体的大片投影轮廓。此为软件近似，FPGA 去马赛克、连接和具体阈值不同，实际显示仍需上板确认。加载入口用 --emit-test 检查，不占用 USB。

## 最终提示词记录（内置 imagegen）

### 原图到自然灰背景版：螺丝

Use case: lighting-weather / high-fidelity photographic retouch. This is a correction of over-retouched images: the user wants the ORIGINAL real snapshot feeling back, NOT a CGI product rendering or sterile cutout. Edit the supplied original photo conservatively; preserve the actual object with its exact geometry, position, perspective, scale, original materials, manufacturing imperfections and natural reflections. Preserve the original landscape aspect ratio and composition. Use a matte, slightly dull, dusty-looking medium warm-neutral GRAY tabletop, roughly RGB 180-190, NOT white or near-white. A faint smooth real tabletop appearance is welcome, but no visible specks, scratches or coarse grain. Low-amplitude very broad illumination variation, not a perfectly flat synthetic background. Keep realistic depth and natural modest photographic contrast, not dramatic studio light. 
Retain a visible but much gentler version of the original cast shadow, in the SAME direction and footprint as the original. Reduce its darkness greatly: about 8-15 gray levels darker than the local gray tabletop. Make the shadow very diffuse with a wide feathered boundary (roughly 20-35 pixels across when the entire photo is reduced to 960 pixels wide). No sharp detached shadow boundary, no hard dark band. Keep a narrow modest contact shadow directly beneath the object so it convincingly rests on the surface rather than floating. Slight shadow edges being detected is acceptable. The shadow should be visually natural and have slow tonal gradients that produce little response to a 3x3 Sobel/Canny edge detector, without erasing the shadow altogether. Favor realism over mathematically pristine edges. No added outlines, glow, edge-map, labels outside the product, watermark, artificial background blur/bokeh or redesigned object.
SUBJECT: the original steel screw lying horizontally with threaded tip at left, wide thin flange/head edge-on at right. Keep the real slightly irregular polished steel reflections and machining marks from the original, not uniform chrome or perfect repeated 3D-model threads. Gently reduce only tiny harsh highlight specks and restore some lower-thread detail with restrained fill light. The upper and lower thread silhouette must remain clear against the gray surface. Don't flatten its shading or brighten the whole screw to pale silver. Preserve the exact head shape and original thread spacing/count. The original shadow is below the body and slightly to the right; retain a light, very soft version under the shaft and under the right flange. Show a believable ordinary camera photograph of the same screw on a gray tabletop.

### 原图到自然灰背景版：卡尺

Use case: lighting-weather / high-fidelity photographic retouch. This is a correction of over-retouched images: the user wants the ORIGINAL real snapshot feeling back, NOT a CGI product rendering or sterile cutout. Edit the supplied original photo conservatively; preserve the actual object with its exact geometry, position, perspective, scale, original materials, manufacturing imperfections and natural reflections. Preserve the original landscape aspect ratio and composition. Use a matte, slightly dull, dusty-looking medium warm-neutral GRAY tabletop, roughly RGB 180-190, NOT white or near-white. A faint smooth real tabletop appearance is welcome, but no visible specks, scratches or coarse grain. Low-amplitude very broad illumination variation, not a perfectly flat synthetic background. Keep realistic depth and natural modest photographic contrast, not dramatic studio light. 
Retain a visible but much gentler version of the original cast shadow, in the SAME direction and footprint as the original. Reduce its darkness greatly: about 8-15 gray levels darker than the local gray tabletop. Make the shadow very diffuse with a wide feathered boundary (roughly 20-35 pixels across when the entire photo is reduced to 960 pixels wide). No sharp detached shadow boundary, no hard dark band. Keep a narrow modest contact shadow directly beneath the object so it convincingly rests on the surface rather than floating. Slight shadow edges being detected is acceptable. The shadow should be visually natural and have slow tonal gradients that produce little response to a 3x3 Sobel/Canny edge detector, without erasing the shadow altogether. Favor realism over mathematically pristine edges. No added outlines, glow, edge-map, labels outside the product, watermark, artificial background blur/bokeh or redesigned object.
SUBJECT: the same real black plastic digital caliper, closed jaws at left, blank LCD, slider at left, yellow scale strip and long black right tail. Retain real molded-plastic fine surface appearance and gentle dark shading instead of an unnaturally perfect black vector shape. Preserve the blank LCD with subtle real reflections, existing blue/red/ivory buttons and exact jaw geometry.
Keep scale lines and printed text readable after reduction of the entire photo to 960 pixels wide. Clean obvious broken/noisy graduations into straight, consistent printed strokes, preserving original major/minor tick positions and counts; modestly strengthen their ink contrast and line weight, but do not turn the tool into an idealized ruler diagram. Original metric labels left to right "70 80 90 100 110 120 130 140 150", units "mm"; top "3 4 5 6" and "in". Preserve exact left text "mm/inch", "OFF", "ON", "ZERO", slightly clearer ivory-white real ink on the black housing. Preserve right text exactly "DL90150B  0-150mm" and "ELECTRONIC DIGITAL CALIPER"; use slightly faded warm ivory ink for grayscale contrast, subtly bold and readable, not glowing pristine computer typography. Keep all text within its original regions and the LCD blank. Retain a very soft faint shadow from the jaws, display body and long beam as in the original photo, predominantly downward/right, no strong shadow rectangles. Realistic slightly used instrument photographed on matte gray tabletop, not CGI/catalog cutout.

### 第二次：稍微加深阴影

Use case: lighting-weather, very small photographic retouch. The supplied image is the current approved natural gray-tabletop version. Change ONLY the existing cast/contact shadow: the user asks for just a little more shadow. Make its existing soft cast shadow approximately 20-30% stronger than currently, roughly another 4-7 grayscale levels of darkness at its strongest diffuse area, with a slightly more apparent contact shadow immediately below the object. Keep the same shadow direction and footprint and keep all distant shadow boundaries very soft, feathered across about 20-35 pixels at a final 960-pixel whole-image width. It should look like a real photographed object resting on the table, with visible but restrained shadow, not a dramatic dark band or a sharply outlined duplicate silhouette. Preserve the entire object, EVERY existing letter, number, measurement graduation, its geometry, materials, reflections, position, size, the exact same crop and aspect ratio, the existing dull medium warm-gray tabletop color and its natural fine texture, and all illumination OUTSIDE the shadow absolutely unchanged. Do not beautify or redraw the object, sharpen it, erase its real texture, add any markings, alter any text or make the background lighter. No outline, no halo, no white background, no CGI look. The goal remains mostly clean Canny edges, but a few faint shadow edges are acceptable. This is only a subtle strengthening of the current shadow.

### 第三次：稍微扩大阴影范围

Use case: lighting-weather. Make ONE small local adjustment to the current supplied photograph. The user now requests: "Expand the shadow area a little more." Keep the present shadow depth/darkness and the gray tabletop appearance. Enlarge the existing diffuse cast shadow footprint by roughly 20-25% outward from the object, mainly farther downward and a little to the right, in exactly the current light direction. Spread the shadow farther across the tabletop while keeping a natural wide, gradual, feathered transition. For the screw this means a slightly wider soft oval/shaft shadow and a gently larger soft shadow below the right flange. For a caliper this means a modestly broader soft shadow below the long ruler beam, the left display body and jaws. Do not make the darkest shadow darker; this request is for slightly greater AREA, not higher contrast. Do not create a hard rectangular patch or sharp detached duplicate silhouette. Maintain a credible real photographed object resting on the surface. Preserve EVERYTHING ELSE pixel-faithfully: object shape, position, scale and perspective, original frame/aspect ratio and crop, surface texture and reflections, blank LCD if present, EVERY existing printed letter, number and ruler graduation, color and lighting. No beautification, no object redraw, no artificial outlines, no new text. Keep the background dull warm gray, not white. Soft low-gradient shadow is important for a mostly clean Canny edge map, but a little shadow detection is acceptable. Only modestly broaden the existing shadow.

