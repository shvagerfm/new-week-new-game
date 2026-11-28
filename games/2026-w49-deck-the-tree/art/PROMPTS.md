# Deck the Tree: промпти для ChatGPT (генерація арту)

Гра поки малює все заглушками. Щойно в папці `art/` з'являється PNG з назвою з таблиці нижче, гра бере його замість заглушки (код: `art.gd`). Можна замінювати по одному файлу.

## Як користуватись

1. Почни новий чат у ChatGPT і спершу встав **блок стилю** (нижче), щоб усі картинки вийшли в одному стилі. Потім по одному промпту на картинку, в тому ж чаті.
2. Для спрайтів (усе, крім фонів) проси прозорий фон. Якщо прозорості немає, прибери фон (наприклад, remove.bg або Photoshop) і збережи як PNG.
3. Обріж зайві поля, зменш до розміру з таблиці й поклади в `games/2026-w49-deck-the-tree/art/` під точною назвою.
4. Промпти англійською: так ChatGPT стабільніше тримає стиль. Текст на картинках не потрібен ніде.

| Файл | Що це | Розмір у грі | Фон |
| --- | --- | --- | --- |
| `elf.png` | Ельф, що кидає | 512×768 | прозорий |
| `ornament.png` | Куля-прикраса (біла, гра фарбує сама) | 128×128 | прозорий |
| `tier_forest.png` | Ярус ялинки згори, світ 1 | 1024×1024 | прозорий |
| `tier_gingerbread.png` | Ярус, світ 2 | 1024×1024 | прозорий |
| `tier_ice.png` | Ярус, світ 3 | 1024×1024 | прозорий |
| `tier_workshop.png` | Ярус, світ 4 | 1024×1024 | прозорий |
| `tier_square.png` | Ярус, світ 5 | 1024×1024 | прозорий |
| `boss_star.png` | Бос: зірка-верхівка з обличчям | 1024×1024 | прозорий |
| `bg_forest.png` … `bg_square.png` | Фони 5 світів | 1080×1920 | повний |
| `icon.png` | Іконка гри | 1024×1024 | повний |

---

## 0. Блок стилю (вставити першим)

```
I'm making a cozy Christmas mobile game called "Deck the Tree". A cheerful elf decorates a spinning Christmas tree by throwing ornaments at it. Please keep ALL images in this chat in one consistent style:

- Style: polished 2D casual mobile game art, soft cel shading with gentle gradients, clean dark outlines (2–3 px at 1024 px), rounded friendly shapes, slightly chunky proportions. Think of a premium cozy holiday puzzle game, not pixel art, not photorealistic, not 3D render.
- Lighting: soft warm key light from the upper left, subtle rim light, small glossy highlights.
- Palette: deep evergreen greens (#1f5a36, #2f7d4a, #49a061), Christmas red (#d8343a), warm gold (#f6c343), snow white (#eef4ff), night blue (#0d1b2e). Saturated but not neon.
- No text, no letters, no logos, no watermarks, no UI.
- Sprites: a single centered object on a fully transparent background (PNG with alpha), nothing else in the frame, no ground shadow unless I ask.

Reply "ready" and wait for my first request.
```

## 1. Ельф: `elf.png`

```
Sprite: a cute Christmas elf character, full body, seen from the front, standing on the ground and about to throw. Young, cheerful, big friendly eyes, rosy cheeks, pointy ears sticking out sideways, small smile. Wears a green tunic with a brown belt and gold buckle, red-and-white striped stockings, curly green shoes with tiny bells, and a tall floppy red hat with white fur trim and a white pompom. The right arm is raised above the head holding nothing (the game adds the ornament), the left arm relaxed. Proportions: head about one third of the height. Centered, the whole body fits inside the frame with a little margin. Transparent background, portrait orientation 2:3.
```

Якщо треба анімація кидка, другим кадром: `Same elf, same pose and framing, but the right arm swung forward and down after a throw, body leaning slightly forward. Keep everything else identical.` (назва `elf_throw.png`, гра його поки не використовує).

## 2. Прикраса: `ornament.png`

```
Sprite: one round Christmas ornament ball seen from the side, with a small gold metal cap and a tiny loop on top. The ball is pure white / very light silver glass (the game tints it to different colors), with a soft glossy highlight in the upper left and a subtle darker edge so it still reads when tinted. No pattern. The cap points straight up. Centered, square 1:1, the ball fills about 80% of the frame. Transparent background.
```

## 3. Яруси ялинки (вид згори)

Важливо для всіх ярусів: **ідеальне коло, вид строго згори, коло торкається країв картинки**, центр картинки = центр стовбура. Гра обертає картинку навколо центру.

### `tier_forest.png`: світ 1, Лісова ялинка

```
Sprite: one tier (layer) of a fir Christmas tree seen from directly above (top-down, orthographic), forming a perfect circle that touches all four edges of a square 1:1 image. Dense layered fir branches radiate from the center; the outer rim is a ring of soft spiky branch tips. Three concentric rings of branches, slightly lighter towards the center, with a light dusting of snow on the tips. In the exact center, a small round cut of the brown trunk with tree rings. A thin string of small warm white fairy lights runs around in a circle at about 60% of the radius. Evergreen palette. Transparent background outside the circle.
```

### `tier_gingerbread.png`: світ 2, Пряникове містечко

```
Same top-down tree tier as before (perfect circle touching the edges, trunk in the exact center, square 1:1, transparent outside), but themed for a gingerbread town: the branch tips are frosted with white icing like on gingerbread cookies, a ring of small gingerbread-cookie stars and tiny candy buttons sits at 60% of the radius, warm cinnamon-brown accents.
```

### `tier_ice.png`: світ 3, Крижане озеро

```
Same top-down tree tier (perfect circle touching the edges, trunk in the exact center, square 1:1, transparent outside), but frozen: the needles are frosty blue-green, covered in hoarfrost and tiny icicles on the rim, a ring of pale blue crystal snowflakes at 60% of the radius, cool cyan highlights.
```

### `tier_workshop.png`: світ 4, Майстерня Санти

```
Same top-down tree tier (perfect circle touching the edges, trunk in the exact center, square 1:1, transparent outside), themed for Santa's toy workshop: a red-and-white ribbon garland spirals around at 60% of the radius, with small wooden toy details (tiny drums, wooden stars) tucked between the branches.
```

### `tier_square.png`: світ 5, Новорічна площа

```
Same top-down tree tier (perfect circle touching the edges, trunk in the exact center, square 1:1, transparent outside), themed for a grand New Year's Eve city tree: rich deep green, a ring of glowing golden bulb lights at 60% of the radius, small gold tinsel sparkles on the branch tips, a festive magical glow.
```

## 4. Бос: `boss_star.png`

```
Sprite: the boss of the game, a big round golden Christmas tree-top star medallion seen from the front. A perfect circle that touches all four edges of a square 1:1 image: a thick gold rim, and inside it an embossed five-pointed star in lighter gold. The star has a grumpy but cute face in the middle (frowning eyebrows, small eyes, a pouting mouth), like a cartoon boss you want to defeat, not scary. Glossy metallic gold, warm highlights. The face is upright. Transparent background outside the circle.
```

Для п'яти босів можна зробити варіанти (поки гра бере один файл): сова-вартова, пряниковий велетень, крижана зірка, заводна зірка з шестернями, Північна зірка. Скажи, і я додам по файлу на світ.

## 5. Фони: `bg_<світ>.png` (1080×1920, вертикальні)

Спільне для всіх фонів: нижня третина картинки (від 70% висоти вниз) спокійна, рівний сніг, бо там стоїть ельф і кнопки. Центр не перевантажений, бо там крутиться ярус.

### `bg_forest.png`

```
Background, vertical 9:16 (1080x1920): a quiet snowy forest clearing at night. Deep night-blue sky with soft stars and a pale moon in the upper right, gentle falling snow. Rows of dark fir tree silhouettes in the distance, darker and simpler than foreground art so sprites stand out. The bottom 30% of the image is a flat, smooth snowy ground with soft blue shadows and nothing on it. The middle of the image is open sky, calm and uncluttered. Low contrast, slightly blurred depth. No characters, no text.
```

### `bg_gingerbread.png`

```
Same composition as the forest background (vertical 9:16, calm open middle, flat empty snowy ground in the bottom 30%), but a cozy gingerbread village at dusk: small gingerbread houses with icing roofs and warm glowing windows far in the background, purple-pink dusk sky, gentle snowfall.
```

### `bg_ice.png`

```
Same composition (vertical 9:16, calm open middle, flat empty snowy-ice ground in the bottom 30%), but a frozen lake at night: smooth blue ice with subtle reflections, frosted pines on the far shore, a soft green-blue aurora in the sky.
```

### `bg_workshop.png`

```
Same composition (vertical 9:16, calm open middle, flat empty floor in the bottom 30%), but inside Santa's toy workshop: warm red-burgundy wooden walls in soft focus, shelves with toys and a lit fireplace far in the background, a window showing falling snow, warm cozy light. The floor in the bottom 30% is a plain wooden floor with a light snow-white rug, empty.
```

### `bg_square.png`

```
Same composition (vertical 9:16, calm open middle, flat empty snowy square in the bottom 30%), but a city square on New Year's Eve: deep indigo night sky with colorful fireworks far in the background, silhouettes of old town buildings with lit windows and string lights, soft bokeh glow.
```

## 6. Іконка: `icon.png`

```
App icon, square 1:1, full background (no transparency): the cute elf from before, head and shoulders, joyfully tossing a shiny red ornament towards a small decorated Christmas tree with a golden star. Night-blue background with a soft radial glow and a few snowflakes. Bold, readable at small size, centered composition with a safe margin around the edges. No text.
```

## 7. Додатково (за бажанням)

- `title.png`: логотип-напис для меню. ChatGPT інколи плутає літери, тому напис можна зробити шрифтом у грі; якщо хочеш картинкою: `Game logo, the words "Deck the Tree" in a playful chunky festive font, white letters with red outline and a sprinkle of snow on top, a small golden star on top of the letter "T", transparent background, wide 3:1.`
- Цукерка й золота зірка на ободі ярусу поки малюються кодом. Якщо захочеш спрайти: `candy.png` і `goal_star.png`, 128×128, прозорий фон.
