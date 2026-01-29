//! HTML and SVG Element Tags
//!
//! Auto-generated from WHATWG HTML Living Standard
//! Source: https://html.spec.whatwg.org/multipage/indices.html
//!
//! DO NOT EDIT MANUALLY - Run `node tools/gen-elements` to regenerate

/// HTML and SVG element tag names
pub const ElementTag = enum {
    // ===== HTML Elements =====
    /// Base URL and default target navigable for hyperlinks and forms
    base,
    /// Container for document metadata
    head,
    /// Link metadata
    link,
    /// Text metadata
    meta,
    /// Embedded styling information
    style,
    /// Document title
    title,
    /// Contact information for a page or article element
    address,
    /// Self-contained syndicatable or reusable composition
    article,
    /// Sidebar for tangentially related content
    aside,
    /// Document body
    body,
    /// Footer for a page or section
    footer,
    /// Introductory or navigational aids for a page or section
    header,
    /// Heading level 1
    h1,
    /// Heading level 2
    h2,
    /// Heading level 3
    h3,
    /// Heading level 4
    h4,
    /// Heading level 5
    h5,
    /// Heading level 6
    h6,
    /// Heading container
    hgroup,
    /// Container for the dominant contents of the document
    main,
    /// Section with navigational links
    nav,
    /// Generic document or application section
    section,
    /// Container for search controls
    search,
    /// A section quoted from another source
    blockquote,
    /// Content for corresponding dt element(s)
    dd,
    /// Generic flow container, or container for name-value groups in dl elements
    div,
    /// Association list consisting of zero or more name-value groups
    dl,
    /// Legend for corresponding dd element(s)
    dt,
    /// Caption for figure
    figcaption,
    /// Figure with optional caption
    figure,
    /// Thematic break
    hr,
    /// List item
    li,
    /// Menu of commands
    menu,
    /// Ordered list
    ol,
    /// Paragraph
    p,
    /// Block of preformatted text
    pre,
    /// List
    ul,
    /// Hyperlink
    a,
    /// Abbreviation
    abbr,
    /// Keywords
    b,
    /// Text directionality isolation
    bdi,
    /// Text directionality formatting
    bdo,
    /// Line break, e.g. in poem or postal address
    br,
    /// Title of a work
    cite,
    /// Computer code
    code,
    /// Machine-readable equivalent
    data,
    /// Defining instance
    dfn,
    /// Stress emphasis
    em,
    /// Alternate voice
    i,
    /// User input
    kbd,
    /// Highlight
    mark,
    /// Quotation
    q,
    /// Parenthesis for ruby annotation text
    rp,
    /// Ruby annotation text
    rt,
    /// Ruby annotation(s)
    ruby,
    /// Inaccurate text
    s,
    /// Computer output
    samp,
    /// Side comment
    small,
    /// Generic phrasing container
    span,
    /// Importance
    strong,
    /// Subscript
    sub,
    /// Superscript
    sup,
    /// Machine-readable equivalent of date- or time-related data
    time,
    /// Unarticulated annotation
    u,
    /// Line breaking opportunity
    wbr,
    /// A removal from the document
    del,
    /// An addition to the document
    ins,
    /// Audio player
    audio,
    /// Scriptable bitmap canvas
    canvas,
    /// Plugin
    embed,
    /// Child navigable
    iframe,
    /// Image
    img,
    /// Image, child navigable, or plugin
    object,
    /// Image container for responsive images
    picture,
    /// Image source for img or media source for video or audio
    source,
    /// Timed text track
    track,
    /// Video player
    video,
    /// Table caption
    caption,
    /// Table column
    col,
    /// Group of columns in a table
    colgroup,
    /// Table
    table,
    /// Group of rows in a table
    tbody,
    /// Table cell
    td,
    /// Group of footer rows in a table
    tfoot,
    /// Table header cell
    th,
    /// Group of heading rows in a table
    thead,
    /// Table row
    tr,
    /// Button control
    button,
    /// Container for options for combo box control
    datalist,
    /// Group of form controls
    fieldset,
    /// User-submittable form
    form,
    /// Form control
    input,
    /// Caption for a form control
    label,
    /// Caption for fieldset
    legend,
    /// Gauge
    meter,
    /// Group of options in a list box
    optgroup,
    /// Option in a list box or combo box control
    option,
    /// Calculated output value
    output,
    /// Progress bar
    progress,
    /// List box control
    select,
    /// Mirrors content from an option
    selectedcontent,
    /// Multiline text controls
    textarea,
    /// Disclosure control for hiding details
    details,
    /// Dialog box or window
    dialog,
    /// Caption for details
    summary,
    /// Fallback content for script
    noscript,
    /// Embedded script
    script,
    /// Shadow tree slot
    slot,
    /// Template
    template,
    /// Hyperlink or dead area on an image map
    area,
    /// Root element
    html,
    /// Image map
    map,

    // ===== Obsolete/Deprecated HTML Elements =====
    /// Abbreviation (obsolete, use abbr)
    acronym,
    /// Java applet (obsolete, use object or embed)
    applet,
    /// Default font style (obsolete)
    basefont,
    /// Larger text (obsolete, use CSS)
    big,
    /// Blinking text (obsolete)
    blink,
    /// Centered content (obsolete, use CSS)
    center,
    /// Command button (obsolete)
    command,
    /// Shadow DOM insertion point (obsolete)
    content,
    /// Directory list (obsolete, use ul)
    dir,
    /// Custom element definition (obsolete)
    element,
    /// Font styling (obsolete, use CSS)
    font,
    /// Frame in frameset (obsolete, use iframe)
    frame,
    /// Frame container (obsolete)
    frameset,
    /// Single-line text input (obsolete, use input)
    isindex,
    /// Key-pair generator (obsolete)
    keygen,
    /// Code listing (obsolete, use pre)
    listing,
    /// Scrolling text (obsolete)
    marquee,
    /// Menu item (obsolete)
    menuitem,
    /// Multi-column layout (obsolete, use CSS)
    multicol,
    /// Next ID (obsolete)
    nextid,
    /// Non-breaking text (obsolete, use CSS)
    nobr,
    /// Fallback for embed (obsolete)
    noembed,
    /// Fallback for frames (obsolete)
    noframes,
    /// Plugin parameter (obsolete)
    param,
    /// Plain text (obsolete, use pre)
    plaintext,
    /// Ruby base (obsolete)
    rb,
    /// Ruby text container (obsolete)
    rtc,
    /// Shadow tree root (obsolete)
    shadow,
    /// Spacing (obsolete, use CSS)
    spacer,
    /// Strikethrough (obsolete, use s or del)
    strike,
    /// Teletype text (obsolete, use code)
    tt,
    /// Example (obsolete, use pre and code)
    xmp,

    // ===== SVG Elements (case-sensitive) =====
    /// Animate element properties over time
    animate,
    /// Animate element along a motion path
    animateMotion,
    /// Animate transformation attributes
    animateTransform,
    /// Set attribute value for specified duration
    set,
    /// Container for referenced elements
    defs,
    /// Container for grouping elements
    g,
    /// Marker symbol for line/path ends
    marker,
    /// Alpha mask for compositing
    mask,
    /// Pattern for filling elements
    pattern,
    /// SVG document fragment
    svg,
    /// Reusable graphic symbol
    symbol,
    /// Reference to another element
    use,
    /// Text description of container element
    desc,
    /// Metadata about SVG content
    metadata,
    /// Human-readable title for element
    title,
    /// Blend two objects together
    feBlend,
    /// Apply matrix transformation on color values
    feColorMatrix,
    /// Component-wise remapping
    feComponentTransfer,
    /// Combine images using Porter-Duff operations
    feComposite,
    /// Apply matrix convolution filter
    feConvolveMatrix,
    /// Light element using its alpha channel as bump map
    feDiffuseLighting,
    /// Use pixel values to displace image
    feDisplacementMap,
    /// Distant light source for lighting filter
    feDistantLight,
    /// Drop shadow effect
    feDropShadow,
    /// Fill filter region with color and opacity
    feFlood,
    /// Transfer function for alpha component
    feFuncA,
    /// Transfer function for blue component
    feFuncB,
    /// Transfer function for green component
    feFuncG,
    /// Transfer function for red component
    feFuncR,
    /// Blur effect
    feGaussianBlur,
    /// Fetch external image
    feImage,
    /// Composite input image layers
    feMerge,
    /// Layer in feMerge
    feMergeNode,
    /// Erode or dilate input image
    feMorphology,
    /// Offset input image
    feOffset,
    /// Point light source for lighting filter
    fePointLight,
    /// Specular lighting effect
    feSpecularLighting,
    /// Spot light source for lighting filter
    feSpotLight,
    /// Fill rectangle with tiled pattern
    feTile,
    /// Create image using Perlin turbulence
    feTurbulence,
    /// Container for filter primitives
    filter,
    /// Linear gradient definition
    linearGradient,
    /// Radial gradient definition
    radialGradient,
    /// Gradient stop
    stop,
    /// Circle shape
    circle,
    /// Ellipse shape
    ellipse,
    /// External image reference
    image,
    /// Straight line
    line,
    /// Arbitrary path shape
    path,
    /// Closed polygon shape
    polygon,
    /// Connected line segments
    polyline,
    /// Rectangle shape
    rect,
    /// Text content
    text,
    /// Text along a path
    textPath,
    /// Text span within text element
    tspan,
    /// Clipping path definition
    clipPath,
    /// Foreign namespace content
    foreignObject,
    /// Motion path reference
    mpath,
    /// Conditional processing
    switch,
    /// Particular view of SVG content
    view,

    // ===== Special =====
    /// Document fragment container
    fragment,

    /// Returns the string representation of the tag
    pub fn toString(self: ElementTag) []const u8 {
        return @tagName(self);
    }

    /// Check if this is an SVG element
    pub fn isSvg(self: ElementTag) bool {
        return @intFromEnum(self) >= @intFromEnum(ElementTag.animate);
    }

    /// Check if this is an obsolete/deprecated element
    pub fn isObsolete(self: ElementTag) bool {
        const start = @intFromEnum(ElementTag.acronym);
        const end = @intFromEnum(ElementTag.xmp);
        const val = @intFromEnum(self);
        return val >= start and val <= end;
    }
};
