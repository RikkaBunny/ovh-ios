# 透明背景版本 · 2026-10-04

使用内置 image_gen 编辑工具对原五张功能插图逐张执行背景移除，参数 `transparent_background: true`，保留原造型、材质与蓝紫配色。接口未返回可核验的模型版本。最终网页资源为带真实 Alpha 通道的 RGBA WebP（质量 92），转换格式时逐像素核对 Alpha 与生成 PNG 完全一致，没有另写抠图算法。

五张素材的 Alpha 范围均为 0–255，四个角像素均为 0，均包含完全透明像素与半透明边缘 / 阴影。总大小 834,396 字节。网页移除 `mix-blend-mode: multiply`，使用 `alpha-20261004` 资源版本。

| 素材 | 最终路径 | 尺寸 | 文件字节 | 完全透明像素 | 部分透明像素 |
| --- | --- | --- | ---: | ---: | ---: |
| tasks | [feature-tasks.webp](../assets/feature-tasks.webp) | 1254 × 1254 | 165,562 | 712,017 | 859,413 |
| regions | [feature-regions.webp](../assets/feature-regions.webp) | 1254 × 1254 | 201,368 | 793,111 | 778,287 |
| install | [feature-install.webp](../assets/feature-install.webp) | 1254 × 1254 | 130,590 | 932,173 | 639,643 |
| pairing | [feature-pairing.webp](../assets/feature-pairing.webp) | 1254 × 1254 | 163,106 | 564,881 | 1,005,862 |
| scan | [feature-scan.webp](../assets/feature-scan.webp) | 1254 × 1254 | 173,770 | 945,374 | 626,297 |

共同编辑提示词（每次输入只有对应原插图，角色为 edit target）：

```text
Use case: background-extraction. Asset type: existing OVH CP website feature illustration. The supplied image is the EDIT TARGET. Remove only its white background and floor/backdrop, producing genuine RGBA transparency with alpha 0 in the empty space and all four corners. Preserve the existing object group, its exact composition, camera angle, silhouette, white porcelain and frosted-glass materials, blue-violet colors, highlights, symbols and proportions. Keep white portions of the objects opaque; do not key out their white surfaces. Preserve clean anti-aliased edges. Retain only a small soft contact shadow as semi-transparent alpha, with no opaque white floor, halo, rectangle or backdrop. Where an original light beam or glass is translucent, retain its natural transparency. Square framing with all objects fully inside the frame and similar scale to the original. No additions, no text, no watermark. Do not paint a checkerboard; the background must be actual transparent pixels.
```

原始透明 PNG 由生成工具保留在本地生成目录，网页仅部署上表五张 WebP。以下为原白底版本的生成记录，当前资源已经替换为上方的透明版本。

---

# 官网功能插图 · 2026-10-04

使用内置 `image_gen` 图像生成工具；本次接口未返回可核验的模型版本。前两张按同一风格规范生成，后三张使用任务插图作为材质、光线和配色参考。所有功能插图统一纯白背景、白色瓷质与磨砂玻璃、蓝紫点缀，保持真实应用截图与功能二维码。

最终素材保存于 `website/assets/`；以下均为生成后保留构图的 WebP 网页版本（质量 92），不包含代码重绘。原始生成 PNG 保留在本地生成工具目录，不作为网页资源发布。正文提供语义信息，插图使用空 alt 作为装饰，不替代真实的配对二维码。

## feature-tasks.webp

最终路径：`website/assets/feature-tasks.webp`。

生成提示词：

```text
Use case: stylized-concept. Asset type: premium feature illustration for the OVH CP technology product website. Style: restrained high-end 3D product icon, elegant rounded geometry, porcelain white and frosted glass surfaces with small cobalt blue (#2563eb) and violet (#9333ea) accents. Soft studio lighting, gentle realistic ambient occlusion, crisp refined edges, no grain. Composition: a single centered coherent object group in a square image, occupies about 70% of the frame with generous white space, slight isometric three-quarter view. Background: absolutely pure white #ffffff, smooth and seamless, a delicate contact shadow only, no background gradient, no scenery, no frame, no tile. No text, letters, numbers, logos, watermark, labels, characters, or UI screenshots. Readable at a 280px display size. Match the light white/gray website and blue-purple palette. This is an expressive feature icon, not a generic stock photo. Subject: server inventory purchasing and automated task tracking. A compact elegant stack of three cloud server units in white porcelain with blue-violet status details, accompanied by one floating translucent rounded task card with three abstract raised horizontal rows and clear completed check marks, plus one small integrated circular time/progress dial. The server and task elements form one balanced polished icon, minimal and distinct, plenty of uncluttered breathing room. Avoid dense wires, scattered unrelated objects, coins, carts, shopping bags, overly shiny neon effects.
```

## feature-regions.webp

最终路径：`website/assets/feature-regions.webp`。

生成提示词：

```text
Use case: stylized-concept. Asset type: premium feature illustration for the OVH CP technology product website. Style: restrained high-end 3D product icon, elegant rounded geometry, porcelain white and frosted glass surfaces with small cobalt blue (#2563eb) and violet (#9333ea) accents. Soft studio lighting, gentle realistic ambient occlusion, crisp refined edges, no grain. Composition: a single centered coherent object group in a square image, occupies about 70% of the frame with generous white space, slight isometric three-quarter view. Background: absolutely pure white #ffffff, smooth and seamless, a delicate contact shadow only, no background gradient, no scenery, no frame, no tile. No text, letters, numbers, logos, watermark, labels, characters, or UI screenshots. Readable at a 280px display size. Match the light white/gray website and blue-purple palette. This is an expressive feature icon, not a generic stock photo. Subject: multi-region accounts and unified cloud server management. An elegant frosted glass globe with refined white raised continent silhouettes, encircled by a slim cobalt-to-violet orbital connection ribbon linking three tiny white cloud server modules with restrained blue status indicators. Globe is the clear dominant focal point, the three regional nodes are small, coherently connected, visually balanced. Minimal premium cloud infrastructure illustration, no busy network meshes, no dark continents, no floating labels, no country flags, no cartoon faces, no neon.
```

## feature-install.webp

最终路径：`website/assets/feature-install.webp`。

生成提示词：

```text
Use case: stylized-concept. Asset type: a new independent square feature icon for the OVH CP light-themed technology product website. The referenced image is STYLE REFERENCE ONLY, not an edit target: match its exact porcelain-white and frosted-glass material, refined rounded 3D modeling, restrained cobalt blue (#2563eb) to violet (#9333ea) accents, soft studio light, realistic delicate contact shadow, and elegant three-quarter camera angle. Create a different subject described below. Pure white #ffffff seamless background, no gray backdrop, no gradient background, no card border or tile, no scenery. One minimal coherent centered object group, about 70% frame coverage with generous white space. Must be recognizable at 160px. No text, no letters, numbers, logos, watermark, labels or UI screenshot. No hands, people, stock clipart, neon, grain, or unnecessary ornaments. Subject: install the mobile application. A single elegant upright modern smartphone with a white porcelain body, a clean frosted-glass screen bearing one large cobalt-blue-to-violet downward download arrow entering a subtle rounded download tray. Beside its lower edge, one small white cloud symbol makes the cloud app purpose clear. The screen contains only the download symbol, no UI, no words, no app logo. Simple substantial 3D forms with the same beautiful materials as the reference.
```

## feature-pairing.webp

最终路径：`website/assets/feature-pairing.webp`。

生成提示词：

```text
Use case: stylized-concept. Asset type: a new independent square feature icon for the OVH CP light-themed technology product website. The referenced image is STYLE REFERENCE ONLY, not an edit target: match its exact porcelain-white and frosted-glass material, refined rounded 3D modeling, restrained cobalt blue (#2563eb) to violet (#9333ea) accents, soft studio light, realistic delicate contact shadow, and elegant three-quarter camera angle. Create a different subject described below. Pure white #ffffff seamless background, no gray backdrop, no gradient background, no card border or tile, no scenery. One minimal coherent centered object group, about 70% frame coverage with generous white space. Must be recognizable at 160px. No text, no letters, numbers, logos, watermark, labels or UI screenshot. No hands, people, stock clipart, neon, grain, or unnecessary ornaments. Subject: generate a device pairing code in the web console. One elegant compact desktop monitor with white porcelain frame and frosted screen displaying a large abstract blue-violet square pairing-pattern symbol, accompanied by a small translucent raised key/check badge. The pattern is a decorative visual suggestion of QR pairing, NOT an actual functional QR code. Large clean squares and generous space, no tiny dense random text or complicated pixels. No keyboard, no desk, no actual code or numbers.
```

## feature-scan.webp

最终路径：`website/assets/feature-scan.webp`。

生成提示词：

```text
Use case: stylized-concept. Asset type: a new independent square feature icon for the OVH CP light-themed technology product website. The referenced image is STYLE REFERENCE ONLY, not an edit target: match its exact porcelain-white and frosted-glass material, refined rounded 3D modeling, restrained cobalt blue (#2563eb) to violet (#9333ea) accents, soft studio light, realistic delicate contact shadow, and elegant three-quarter camera angle. Create a different subject described below. Pure white #ffffff seamless background, no gray backdrop, no gradient background, no card border or tile, no scenery. One minimal coherent centered object group, about 70% frame coverage with generous white space. Must be recognizable at 160px. No text, no letters, numbers, logos, watermark, labels or UI screenshot. No hands, people, stock clipart, neon, grain, or unnecessary ornaments. Subject: scan and connect the mobile app to the web backend. An elegant white porcelain smartphone tilted slightly toward a small floating frosted-glass square pairing-pattern card. A thin blue-violet scanning beam links the phone screen and pairing card, and one small blue check badge signals successful connection. The phone has only a simple scan-frame symbol, no text or UI. The pairing pattern is decorative, not a functional QR code. Minimal coherent polished icon with generous white space.
```
