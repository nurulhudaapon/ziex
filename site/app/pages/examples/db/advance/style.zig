const zx = @import("zx");
const S = zx.Style;

pub const container: S = .{
    .padding = .px2(24, 0),
};

pub const shell: S = .{
    .width = .percent(100),
    .max_width = .px(960),
    .display = .flex,
    .flex_direction = .column,
};

pub const hero: S = .{
    .background_color = .Canvas,
    .padding = .px2(28, 28),
    .border_radius = .px(16),
    .border = .solid,
    .border_width = .px(1),
    .border_color = .GrayText,
};

pub const eyebrow: S = .{
    .font_size = .px(12),
    .font_weight = .bold,
    .letter_spacing = .px(1),
    .text_transform = .uppercase,
    .color = .kw("var(--link-color)"),
    .margin_bottom = .px(10),
};

pub const hero_title: S = .{
    .font_size = .px(34),
    .font_weight = .bold,
    .margin_bottom = .px(14),
    .line_height = .px(46),
};

pub const hero_text: S = .{
    .font_size = .px(16),
    .max_width = .px(720),
    .color = .kw("var(--subtitle-color)"),
    .line_height = .px(28),
};

pub const stats_grid: S = .{
    .display = .flex,
    .flex_direction = .column,
    .margin_top = .px(20),
};

pub const stat_card: S = .{
    .background_color = .Canvas,
    .padding = .px2(20, 20),
    .border_radius = .px(14),
    .border = .solid,
    .border_width = .px(1),
    .border_color = .GrayText,
};

pub const stat_card_top: S = .{
    .background_color = .Canvas,
    .padding = .px2(20, 20),
    .border_radius = .px(14),
    .border = .solid,
    .border_width = .px(1),
    .border_color = .GrayText,
    .margin_top = .px(14),
};

pub const stat_label: S = .{
    .font_size = .px(12),
    .font_weight = .bold,
    .letter_spacing = .px(1),
    .text_transform = .uppercase,
    .color = .kw("var(--subtitle-color)"),
    .margin_bottom = .px(10),
};

pub const stat_value: S = .{
    .font_size = .px(30),
    .font_weight = .bold,
};

pub const stat_hint: S = .{
    .font_size = .px(14),
    .color = .kw("var(--subtitle-color)"),
    .margin_top = .px(10),
    .line_height = .px(24),
};

pub const content_grid: S = .{
    .display = .flex,
    .flex_direction = .column,
    .margin_top = .px(20),
};

pub const panel: S = .{
    .background_color = .Canvas,
    .padding = .px2(24, 24),
    .border_radius = .px(14),
    .border = .solid,
    .border_width = .px(1),
    .border_color = .GrayText,
};

pub const panel_top: S = .{
    .background_color = .Canvas,
    .padding = .px2(24, 24),
    .border_radius = .px(14),
    .border = .solid,
    .border_width = .px(1),
    .border_color = .GrayText,
    .margin_top = .px(14),
};

pub const panel_title: S = .{
    .font_size = .px(24),
    .font_weight = .bold,
    .margin_bottom = .px(12),
};

pub const panel_text: S = .{
    .font_size = .px(15),
    .color = .kw("var(--subtitle-color)"),
    .margin_bottom = .px(16),
    .line_height = .px(26),
};

pub const list: S = .{
    .display = .flex,
    .flex_direction = .column,
    .padding_left = .px(18),
};

pub const list_item_top: S = .{
    .font_size = .px(15),
    .color = .kw("var(--text-color)"),
    .margin_top = .px(12),
    .line_height = .px(24),
};

pub const list_item: S = .{
    .font_size = .px(15),
    .color = .kw("var(--text-color)"),
    .line_height = .px(24),
};

pub const code_block: S = .{
    .background_color = .Field,
    .padding = .px2(14, 16),
    .border_radius = .px(10),
    .border = .solid,
    .border_width = .px(1),
    .border_color = .GrayText,
    .font_size = .px(14),
};

pub const accent: S = .{
    .color = .kw("var(--link-color)"),
};
