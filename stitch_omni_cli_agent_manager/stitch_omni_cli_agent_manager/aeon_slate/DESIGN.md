# Design System Strategy: The Nocturnal Architect

This design system is a high-performance, editorial-grade framework designed for the "Multi ACP Agent Manager". Moving beyond the constraints of traditional "enterprise" software, this system adopts a **"Nocturnal Architect"** North Star. It treats the interface as a dark, sophisticated workspace where depth is created through light and material properties rather than structural lines. It is designed for focus, leveraging high-contrast accents against a multi-layered charcoal environment to create an atmosphere of precision and authority.

---

### 1. Creative North Star: The Nocturnal Architect
The design system rejects the "flat web" aesthetic. Instead, it embraces **Layered Atmospheric Depth**. By utilizing a monochromatic foundation of deep slates and charcols, we allow the vibrant `primary` (#3fff8b) to act as a "digital laser"—drawing the eye only to what is essential. Layouts should feel intentional and asymmetric, using generous negative space to prevent the density of a chat-based interface from becoming overwhelming.

---

### 2. Color & Materiality

The color palette is rooted in Material Design 3 logic but applied with an editorial eye for high-end digital products.

#### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders to section off large areas of the UI. Separation must be achieved through:
1.  **Background Shifts:** Transitioning from `surface` (#0e0e0e) to `surface-container-low` (#131313).
2.  **Tonal Nesting:** Placing a `surface-container-high` (#20201f) card inside a `surface-container` (#1a1a1a) parent.

#### The Glass & Gradient Rule
To achieve the requested "Modern & Sleek" feel, the sidebar and secondary navigation panels must utilize **Glassmorphism**.
- **Sidebar Material:** `surface-container-lowest` (#000000) at 60% opacity with a 20px Backdrop Blur.
- **CTA Gradients:** Use a subtle linear gradient for primary buttons, moving from `primary` (#3fff8b) at the top-left to `primary-container` (#13ea79) at the bottom-right. This provides a "jewel-like" depth that flat colors lack.

---

### 3. Typography: Editorial Precision

The system utilizes a dual-font pairing to balance character with utility.

*   **Display & Headlines (Manrope):** Chosen for its geometric precision and modern "tech-editorial" feel. Use `display-lg` through `headline-sm` for agent names, high-level metrics, and page titles.
*   **Body & Labels (Inter):** The workhorse for the chat interface. Inter’s tall x-height ensures that even at `body-sm` (0.75rem), agent logs and chat transcripts remain hyper-readable.

**Hierarchy Note:** Use `on-surface-variant` (#adaaaa) for timestamps and secondary metadata to create a "receding" effect, allowing the active conversation (`on-surface` #ffffff) to sit at the visual forefront.

---

### 4. Elevation & Depth: Tonal Layering

We do not use shadows to create "pop"; we use them to simulate **Ambient Light**.

*   **The Layering Principle:** 
    - Base Level: `surface`
    - Navigation/Sidebar: `surface-container-low` (with Glassmorphism)
    - Content Cards: `surface-container-high`
    - Floating Modals: `surface-container-highest`
*   **Ambient Shadows:** For floating elements (like hover-state agent cards), use an extra-diffused shadow: `box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);`.
*   **The Ghost Border:** If a boundary is strictly required for accessibility (e.g., in input fields), use `outline-variant` (#484847) at 20% opacity. Never use 100% opaque borders.

---

### 5. Component Logic

#### Chat Interface (Signature Component)
- **Message Bubbles (Incoming):** Use `surface-container-highest` (#262626) with a `DEFAULT` (0.5rem) corner radius. The tail should be omitted for a cleaner, modern look.
- **Message Bubbles (Outgoing):** Use `secondary-container` (#36485b) to differentiate from the primary green accent, ensuring the green is reserved for *actions* and *status*, not just text containers.
- **Interaction:** On hover, a message bubble should subtly shift to `surface-bright` (#2c2c2c).

#### Buttons & CTAs
- **Primary:** High-vibrancy `primary` (#3fff8b) background with `on-primary` (#005d2c) text. Use `xl` (1.5rem) corner radius for a pill shape that feels friendly yet precise.
- **Secondary:** `outline` (#767575) Ghost Border (20% opacity) with `on-surface` text.

#### Navigation & Tabs
- **Active State:** Instead of a bottom bar, use a 4px vertical "pill" of `primary` light to the left of the active navigation item. 
- **Pinned Items:** Use a `surface-container-highest` background with a subtle glow effect using the `surface-tint` (#3fff8b) at 5% opacity.

#### Input Fields
- **Container:** `surface-container-lowest` (#000000).
- **Active State:** Change only the `outline` color to `primary`. No heavy outer glows; keep the focus on the content.

---

### 6. Do’s and Don’ts

#### Do
- **Use Asymmetry:** Place high-level stats off-center or in overlapping "floating" cards to break the "grid-template" feel.
- **Respect the Blur:** Use backdrop-blur on all sidebar elements to create a sense of the app living in a 3D space.
- **Vary the Greys:** Use the full range of `surface-container` tokens to define hierarchy.

#### Don’t
- **Don't use Divider Lines:** Never use a solid line to separate chat messages or sidebar links. Use 8px–16px of vertical whitespace instead.
- **Don't overuse the Green:** The `primary` color is a high-energy accent. Overusing it will cause eye fatigue in a dark environment. Use it only for active status and primary actions.
- **Don't use Pure Black (#000) for backgrounds:** Except for the `surface-container-lowest` glass panels, always use the deep charcoal `surface` (#0e0e0e) to maintain a premium, "ink-like" quality.

---

### 7. Roundedness Scale Reference
- **Action Elements (Buttons, Chips):** `full` (pill-shaped).
- **Standard Cards/Containers:** `md` (0.75rem).
- **Large Layout Panels (Chat area, Sidebar):** `lg` (1.0rem).