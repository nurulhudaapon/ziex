const in1 = `pub fn Page(allocator: zx.Allocator) zx.Component {
    const is_admin = true;
    const is_logged_in = false;

    return (
        <main @allocator={allocator}>
            <section>
                {if (is_admin) (<p>Admin</p>) else (<p>User</p>)}
            </section>
            <section>
                {if (is_admin) ("Powerful") else ("Powerless")}
            </section>
            <section>
                {if (is_logged_in) {
                    (<p>Welcome, User!</p>)
                } else {
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;


const inIfLiner1 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
<section>
                        {if (is_admin) (<p>Admin</p>) else (<p>User</p>)}
            </section>
            <section>
{if (is_admin) ("Powerful") else ("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner2 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                        {if (is_admin)          (<p>Admin</p>     )    else (<p>User</p>)   }
            </section>
            <section>
{if (is_admin) ("Powerful") else ("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner3 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if(is_admin)(<p>Admin</p>)else(<p>User</p>)}
            </section>
            <section>
                {if(is_admin)("Powerful")else("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner4 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
{if (is_admin) (<p>Admin</p>) else (<p>User</p>)}
            </section>
            <section>
                {if (is_admin) ("Powerful") else ("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner5 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_admin) (<p>Admin</p>) else (<p>User</p>)}
            </section>
<section>
{if (is_admin) ("Powerful") else ("Powerless")}
</section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner6 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if(is_admin)(<p>Admin</p>)else(<p>User</p>)}
            </section>
            <section>
                {if(is_admin)("Powerful")else("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner7 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_admin) (<p>Admin</p>) else (<p>User</p>)}
            </section>
            <section>
                {if (is_admin) ("Powerful") else ("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner8 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_admin) (       <p>Admin</p>)  else (<p>User</p>)}
            </section>
            <section>
                {if (is_admin) ("Powerful") else ("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner9 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {             if             (is_admin) (          <p>Admin</p>) else     (<p>User</p>       )}
            </section>
            <section>
                {         if (           is_admin) (             "Powerful")             else ("Powerless")              }
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner10 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_admin) (<p>Admin</p>) else (<p>User</p>)}
            </section>
            <section>
                {if (is_admin) ("Powerful") else ("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner11 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_admin) (<p>Admin</p>) else (<p>User</p>)}
            </section>
            <section>
                {if (is_admin) ("Powerful") else ("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfLiner12 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_admin) (<p>Admin</p>) else (<p>User</p>)}
            </section>
            <section>
                {if (is_admin) ("Powerful") else ("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const outIfLiner = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_admin = true;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_admin) (<p>Admin</p>) else (<p>User</p>)}
            </section>
            <section>
                {if (is_admin) ("Powerful") else ("Powerless")}
            </section>
        </main>
    );
}

const zx = @import("zx");
`;

const inIfBlock1 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_logged_in) {
                    (<p>Welcome, User!</p>)
                } else {
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfBlock2 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
{if (is_logged_in) {
                    (<p>Welcome, User!</p>)
                } else {
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfBlock3 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if(is_logged_in) {
                    (<p>Welcome, User!</p>)
                } else {
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfBlock4 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_logged_in){
                    (<p>Welcome, User!</p>)
                } else {
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfBlock5 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_logged_in) {
                    (<p>Welcome, User!</p>)
                }else {
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfBlock6 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_logged_in) {
                    (<p>Welcome, User!</p>)
                } else{
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfBlock7 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_logged_in) {
(<p>Welcome, User!</p>)
                } else {
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfBlock8 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_logged_in) {
                    (<p>Welcome, User!</p>)
                } else {
(<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfBlock9 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_logged_in) {
                    (<p>Welcome, User!</p>)
                } else {
                    (<p>Please log in to continue.</p>)
                }  }
            </section>
        </main>
    );
}

const zx = @import("zx");`;

const inIfBlock10 = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_logged_in)  {
                    (<p>Welcome, User!</p>)
                } else {
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");`;


const outIfBlock = `pub fn Page(ctx: zx.PageContext) zx.Component {
    const is_logged_in = false;

    return (
        <main @allocator={ctx.arena}>
            <section>
                {if (is_logged_in) {
                    (<p>Welcome, User!</p>)
                } else {
                    (<p>Please log in to continue.</p>)
                }}
            </section>
        </main>
    );
}

const zx = @import("zx");
`;


const outSwitchBlock = `pub fn Page(allocator: zx.Allocator) zx.Component {
    return (
        <main @allocator={allocator}>
            <section>
                {switch (user_swtc.user_type) {
                    .admin => ("Admin"),
                    .member => ("Member"),
                }}
            </section>
            <section>
                {switch (user_swtc.user_type) {
                    .admin => (<p>Powerful</p>),
                    .member => (<p>Powerless</p>),
                }}
            </section>
        </main>
    );
}
`;

const inSwitchBlock1 = `pub fn Page(allocator: zx.Allocator) zx.Component {

    return (
        <main @allocator={allocator}>
            <section>
                {switch (user_swtc.user_type) {
                    .admin => ("Admin"),
                    .member => ("Member"),
                }}
            </section>
            <section>
                {switch (user_swtc.user_type) {
                    .admin => (<p>Powerful</p>),
                    .member => (<p>Powerless</p>),
                }}
            </section>
        </main>
    );
}`;

const inSwitchBlock2 = `pub fn Page(allocator: zx.Allocator) zx.Component {
    return (
        <main @allocator={allocator}>
            <section>
{switch (user_swtc.user_type) {
                    .admin => ("Admin"),
                    .member => ("Member"),
                }}
            </section>
            <section>
                {switch (user_swtc.user_type) {
                    .admin => (<p>Powerful</p>),
                    .member => (<p>Powerless</p>),
                }}
            </section>
        </main>
    );
}`;

const inSwitchBlock3 = `pub fn Page(allocator: zx.Allocator) zx.Component {
    return (
        <main @allocator={allocator}>
            <section>
                {switch(user_swtc.user_type) {
                    .admin => ("Admin"),
                    .member => ("Member"),
                }}
            </section>
            <section>
                {switch (user_swtc.user_type){
                    .admin => (<p>Powerful</p>),
                    .member => (<p>Powerless</p>),
                }}
            </section>
        </main>
    );
}`;

const inSwitchBlock4 = `pub fn Page(allocator: zx.Allocator) zx.Component {
    return (
        <main @allocator={allocator}>
            <section>
                {switch (user_swtc.user_type) {
.admin => ("Admin"),
.member => ("Member"),
                }}
            </section>
            <section>
                {switch (user_swtc.user_type) {
                    .admin => (<p>Powerful</p>),
                    .member => (<p>Powerless</p>),
                }}
            </section>
        </main>
    );
}`;

const inSwitchBlock5 = `pub fn Page(allocator: zx.Allocator) zx.Component {
    return (
        <main @allocator={allocator}><section>
                {switch (user_swtc.user_type) {
                    .admin =>("Admin"),
                    .member =>("Member"),
                }}
            </section>
            <section>
                {switch (user_swtc.user_type) {
                    .admin => (<p>Powerful</p>),
                    .member => (<p>Powerless</p>),
                }}
            </section>
        </main>
    );
}`;

const inSwitchBlock6 = `pub fn Page(allocator: zx.Allocator) zx.Component {
    return (
        <main @allocator={allocator}>
            <section>
                {switch (user_swtc.user_type) {
                    .admin => ("Admin")  ,
                    .member => ("Member")  ,
                }}
            </section>
            <section>
                {switch (user_swtc.user_type) {
                    .admin => (<p>Powerful</p>)  ,
                    .member => (<p>Powerless</p>)  ,
                }}
            </section>
        </main>
    );
}`;

const inSwitchBlock7 = `pub fn Page(allocator: zx.Allocator) zx.Component {
    return (
        <main @allocator={allocator}>
            <section>
                {switch (user_swtc.user_type) {
                    .admin =>          ("Admin"),
                    .member => ("Member"),
                }}
            </section>
            <section>
                {switch (user_swtc.user_type) 
                
                
                
                {
                                                 .admin => (<p>Powerful</p>),
                    .member => (<p>Powerless</p>),
                }}
            </section>
        </main>
    );
}`;

const inLargeMixexdContent = `pub fn Page(ctx: zx.PageContext) zx.Component {
    return (
<html @allocator={allocator}>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZX Documentation - JSX-like Syntax for Zig</title>
    <link rel="stylesheet" href="./assets/styles.css">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.30.0/themes/prism.min.css" rel="stylesheet">
    <link rel="icon" href={icon_href} type="image/svg+xml">
    <style>
        {
            [@embedFile("../../assets/doc.css"):s]
        }
    </style>
</head>
<body>

    <div class="container">
        <nav class="sidebar">
            <div class="nav-header">
                <div class="nav-header-top">
                    <h1>ZX</h1>
                </div>
                <p class="nav-subtitle">HTML within Zig</p>
            </div>
            <ul class="nav-menu">
                <li><a href="#introduction">Introduction</a></li>
                <li class="nav-item-with-submenu">
                    <a href="#getting-started" class="nav-parent">Getting Started <span class="submenu-arrow">▼</span></a>
                    <ul class="nav-submenu">
                        <li><a href="#getting-started">Quick Start</a></li>
                        <li><a href="#editor-setup">Editor Setup</a></li>
                    </ul>
                </li>
                <li><a href="#control-flow">Control Flow</a></li>
                <li><a href="#expressions">Expressions</a></li>
                <li><a href="#examples">Examples</a></li>
            </ul>
        </nav>
    <main class="content">
        <section id="introduction" class="section">
            <div class="section-header">
                <h2>Introduction</h2>
                <div class="source-code-badge">
                    <a href="https://github.com/nurulhudaapon/zx" target="_blank" rel="noopener noreferrer"
                        class="source-code-badge-link">
                        <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
                            <path
                                d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.012 8.012 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
                        </svg>
                        <span>View Source Code</span>
                    </a>
                </div>
            </div>
            <p>ZX is a Zig library for building web applications with JSX-like syntax. Write declarative UI
                components using familiar JSX patterns, transpiled to efficient Zig code.</p>
            <p>ZX combines the power and performance of Zig with the expressiveness of JSX, enabling you to build
                fast, type-safe web applications. ZX is significantly faster than frameworks like Next.js at SSR.
                <em>Currently 120X faster than Next.js at SSR</em>.
            </p>
        </section>
    
        <section id="getting-started" class="section">
            <h2>Getting Started</h2>
            <p>
                To get started quickly, you can pull the
                <a href="https://github.com/nurulhudaapon/zx-example-portfolio" target="_blank" rel="noopener noreferrer">
                    zx-example-portfolio
                </a>
                repository as a template and try it out yourself.
            </p>
            <p>
                A full, step-by-step getting started guide is currently a work in progress and will be available here soon.
            </p>
        
            <h3 id="editor-setup">Editor Setup</h3>
            <p>
                Enhance your development experience with the official ZX extension for VSCode and Cursor. The extension provides
                syntax highlighting, code completion, and other helpful features for working with <code>.zx</code> files.
                Install it from <a href="https://open-vsx.org/extension/nurulhudaapon/zx" target="_blank"
                    rel="noopener noreferrer">Open VSX</a>.
            </p>
        </section>
    
        <section id="control-flow" class="section">
            <h2>Control Flow</h2>
            <p>ZX supports conditional rendering and iteration using familiar Zig control flow constructs. These expressions
                allow you to conditionally render components or iterate over collections to build dynamic UIs.</p>
        
            <h3>If Statements</h3>
            <p>Use <code>if</code> expressions to conditionally render components based on boolean conditions. The
                <code>else</code> branch is optional and can render alternative content when the condition is false.</p>
            <ExampleBlock id="if" zx_code={zx_example_if} zig_code={zig_example_if} html_code={html_example_if} />
        
            <h3>Switch Statements</h3>
            <p>Use <code>switch</code> expressions to match against enum values or other types. Each case can return either a
                string literal or a component. Switch expressions are particularly useful for rendering different UI based on
                state or user roles.</p>
            <ExampleBlock id="switch" zx_code={zx_example_switch} zig_code={zig_example_switch}
                html_code={html_example_switch} />
        
            <h3>For Loops</h3>
            <p>Use <code>for</code> loops to iterate over arrays, slices, or strings and render a component for each item. The
                loop variable can be used within the component body to display item-specific content. This is ideal for
                rendering lists, tables, or any repeating UI patterns.</p>
            <ExampleBlock id="for" zx_code={zx_example_for} zig_code={zig_example_for} html_code={html_example_for} />
        </section>
    <section id="expressions" class="section"><h2>Expressions</h2>
        <p>ZX provides different expression syntaxes for embedding dynamic content. Each syntax serves a specific purpose:
            rendering components, displaying text safely, or formatting values with custom format specifiers.</p>
    <h3>Component Expressions</h3>
        <p>Use <code>{cmp_expr}</code> to embed a component directly. The expression must evaluate to a
            <code>zx.Component</code> type. This is useful when you want to conditionally render or reuse components
            dynamically.</p>
    <ExampleBlock id="component" zx_code={zx_example_component} zig_code={zig_example_component} html_code={html_example_component} /><h3>Text Expressions</h3>
        <p>Use <code>{txt_expr}</code> to embed text content. All text is automatically HTML-escaped to prevent XSS attacks.
            This is the safe way to display user input or dynamic text content.</p>
    <ExampleBlock id="text" zx_code={zx_example_text} zig_code={zig_example_text} html_code={html_example_text} /><h3>Format Expressions</h3><p>Use<code>{fmt_expr}</code>to format values with custom format specifiers. The format string follows Zig's standard format specifier syntax (e.g., <code>d</code> for decimal, <code>x</code> for hexadecimal). Unlike text expressions, format expressions are not HTML-escaped, making them suitable for numeric formatting and other non-HTML content.</p>
                <ExampleBlock id="format" zx_code={zx_example_format} zig_code={zig_example_format} html_code={html_example_format} />
            </section>

            <section id="examples" class="section">
                <h2>Examples</h2>
                <ul>
                    <li>
                        <strong>This Documentation Site: </strong>
                        <a href="https://ziex.dev" target="_blank" rel="noopener noreferrer">Live</a> |
                        <a href="https://github.com/nurulhudaapon/zx/tree/main/site" target="_blank" rel="noopener noreferrer">Source</a>
                    </li>
                    <li>
                        <strong>A Portfolio Site with Blog: </strong>
                        <a href="https://zigx.nuhu.dev" target="_blank" rel="noopener noreferrer">Live</a> |
                        <a href="https://github.com/nurulhudaapon/zx-example-portfolio" target="_blank" rel="noopener noreferrer">Source</a>
                    </li>
                </ul>
            </section>
        </main>
    </div>

    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.30.0/components/prism-core.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.30.0/plugins/autoloader/prism-autoloader.min.js"></script>
    <script type="module">
        {[@embedFile("../../assets/doc.js"):s]}
    </script>
</body>
</html>
    );
}


fn ExampleBlock(allocator: zx.Allocator, props: ExampleBlockProps) zx.Component {
    return (
        <div class="code-example" @allocator={allocator}>
            <div class="example-code">
                <h4>ZX</h4>
            <pre><code id={zx_code_id} class="language-jsx" contenteditable="true" spellcheck="false" data-full-content={escaped_full_zx} data-truncated-content={truncated_zx_code} title="Click to view full code">{truncated_zx_code}</code></pre>
                </div>
                <div class="example-code">
                    <input type="radio" id={preview_id} name={name_id} class="tab-radio" checked>
                    <input type="radio" id={html_id} name={name_id} class="tab-radio">
                    <input type="radio" id={zig_id} name={name_id} class="tab-radio">
                    <div class="pane-header">
                        <div class="tab-buttons">
                            <label for={preview_id} class="tab-btn">Preview</label>
                            <label for={html_id} class="tab-btn">HTML</label>
                            <label for={zig_id} class="tab-btn">Zig</label>
                        </div>
                    </div>
                    <div class="tab-content" id={preview_content_id}>
                        <div class="preview-wrapper">
                            <iframe class="preview-frame" srcdoc={props.html_code}></iframe>
                        </div>
                    </div>
                    <div class="tab-content" id={html_content_id}>
                        <div class="code-wrapper">
                            <pre><code class="language-markup">{props.html_code}</code></pre>
                        </div>
                    </div>
                    <div class="tab-content" id={zig_content_id}>
                        <div class="code-wrapper">
                            <pre><code class="language-zig" data-full-content={escaped_full_zig} data-truncated-content={truncated_zig_code}>{truncated_zig_code}</code></pre>
                        </div>
                    </div>
                </div>
        </div>
    );
}

const zx = @import("zx");
const std = @import("std");
const util = @import("util.zig");`

export const outLargeMixedContent = `pub fn Page(ctx: zx.PageContext) zx.Component {
    return (
        <html @allocator={allocator}>
        
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ZX Documentation - JSX-like Syntax for Zig</title>
            <link rel="stylesheet" href="./assets/styles.css">
            <link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.30.0/themes/prism.min.css" rel="stylesheet">
            <link rel="icon" href={icon_href} type="image/svg+xml">
            <style>
                {
                    [@embedFile("../../assets/doc.css"):s]
                }
            </style>
        </head>
        
        <body>
        
            <div class="container">
                <nav class="sidebar">
                    <div class="nav-header">
                        <div class="nav-header-top">
                            <h1>ZX</h1>
                        </div>
                        <p class="nav-subtitle">HTML within Zig</p>
                    </div>
                    <ul class="nav-menu">
                        <li><a href="#introduction">Introduction</a></li>
                        <li class="nav-item-with-submenu">
                            <a href="#getting-started" class="nav-parent">Getting Started <span
                                    class="submenu-arrow">▼</span></a>
                            <ul class="nav-submenu">
                                <li><a href="#getting-started">Quick Start</a></li>
                                <li><a href="#editor-setup">Editor Setup</a></li>
                            </ul>
                        </li>
                        <li><a href="#control-flow">Control Flow</a></li>
                        <li><a href="#expressions">Expressions</a></li>
                        <li><a href="#examples">Examples</a></li>
                    </ul>
                </nav>
                <main class="content">
                    <section id="introduction" class="section">
                        <div class="section-header">
                            <h2>Introduction</h2>
                            <div class="source-code-badge">
                                <a href="https://github.com/nurulhudaapon/zx" target="_blank" rel="noopener noreferrer"
                                    class="source-code-badge-link">
                                    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
                                        <path
                                            d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.012 8.012 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
                                    </svg>
                                    <span>View Source Code</span>
                                </a>
                            </div>
                        </div>
                        <p>ZX is a Zig library for building web applications with JSX-like syntax. Write declarative UI
                            components using familiar JSX patterns, transpiled to efficient Zig code.</p>
                        <p>ZX combines the power and performance of Zig with the expressiveness of JSX, enabling you to build
                            fast, type-safe web applications. ZX is significantly faster than frameworks like Next.js at SSR.
                            <em>Currently 120X faster than Next.js at SSR</em>.
                        </p>
                    </section>
        
                    <section id="getting-started" class="section">
                        <h2>Getting Started</h2>
                        <p>
                            To get started quickly, you can pull the
                            <a href="https://github.com/nurulhudaapon/zx-example-portfolio" target="_blank"
                                rel="noopener noreferrer">
                                zx-example-portfolio
                            </a>
                            repository as a template and try it out yourself.
                        </p>
                        <p>
                            A full, step-by-step getting started guide is currently a work in progress and will be available
                            here soon.
                        </p>
        
                        <h3 id="editor-setup">Editor Setup</h3>
                        <p>
                            Enhance your development experience with the official ZX extension for VSCode and Cursor. The
                            extension provides
                            syntax highlighting, code completion, and other helpful features for working with <code>.zx</code>
                            files.
                            Install it from <a href="https://open-vsx.org/extension/nurulhudaapon/zx" target="_blank"
                                rel="noopener noreferrer">Open VSX</a>.
                        </p>
                    </section>
        
                    <section id="control-flow" class="section">
                        <h2>Control Flow</h2>
                        <p>ZX supports conditional rendering and iteration using familiar Zig control flow constructs. These
                            expressions
                            allow you to conditionally render components or iterate over collections to build dynamic UIs.</p>
        
                        <h3>If Statements</h3>
                        <p>Use <code>if</code> expressions to conditionally render components based on boolean conditions. The
                            <code>else</code> branch is optional and can render alternative content when the condition is false.
                        </p>
                        <ExampleBlock id="if" zx_code={zx_example_if} zig_code={zig_example_if} html_code={html_example_if} />
        
                        <h3>Switch Statements</h3>
                        <p>Use <code>switch</code> expressions to match against enum values or other types. Each case can return
                            either a
                            string literal or a component. Switch expressions are particularly useful for rendering different UI
                            based on
                            state or user roles.</p>
                        <ExampleBlock id="switch" zx_code={zx_example_switch} zig_code={zig_example_switch}
                            html_code={html_example_switch} />
        
                        <h3>For Loops</h3>
                        <p>Use <code>for</code> loops to iterate over arrays, slices, or strings and render a component for each
                            item. The
                            loop variable can be used within the component body to display item-specific content. This is ideal
                            for
                            rendering lists, tables, or any repeating UI patterns.</p>
                        <ExampleBlock id="for" zx_code={zx_example_for} zig_code={zig_example_for}
                            html_code={html_example_for} />
                    </section>
                    <section id="expressions" class="section">
                        <h2>Expressions</h2>
                        <p>ZX provides different expression syntaxes for embedding dynamic content. Each syntax serves a
                            specific purpose:
                            rendering components, displaying text safely, or formatting values with custom format specifiers.
                        </p>
                        <h3>Component Expressions</h3>
                        <p>Use <code>{cmp_expr}</code> to embed a component directly. The expression must evaluate to a
                            <code>zx.Component</code> type. This is useful when you want to conditionally render or reuse
                            components
                            dynamically.
                        </p>
                        <ExampleBlock id="component" zx_code={zx_example_component} zig_code={zig_example_component}
                            html_code={html_example_component} />
                        <h3>Text Expressions</h3>
                        <p>Use <code>{txt_expr}</code> to embed text content. All text is automatically HTML-escaped to prevent
                            XSS attacks.
                            This is the safe way to display user input or dynamic text content.</p>
                        <ExampleBlock id="text" zx_code={zx_example_text} zig_code={zig_example_text}
                            html_code={html_example_text} />
                        <h3>Format Expressions</h3>
                        <p>Use<code>{fmt_expr}</code>to format values with custom format specifiers. The format string follows
                            Zig's standard format specifier syntax (e.g., <code>d</code> for decimal, <code>x</code> for
                            hexadecimal). Unlike text expressions, format expressions are not HTML-escaped, making them suitable
                            for numeric formatting and other non-HTML content.</p>
                        <ExampleBlock id="format" zx_code={zx_example_format} zig_code={zig_example_format}
                            html_code={html_example_format} />
                    </section>
        
                    <section id="examples" class="section">
                        <h2>Examples</h2>
                        <ul>
                            <li>
                                <strong>This Documentation Site: </strong>
                                <a href="https://ziex.dev" target="_blank" rel="noopener noreferrer">Live</a> |
                                <a href="https://github.com/nurulhudaapon/zx/tree/main/site" target="_blank"
                                    rel="noopener noreferrer">Source</a>
                            </li>
                            <li>
                                <strong>A Portfolio Site with Blog: </strong>
                                <a href="https://zigx.nuhu.dev" target="_blank" rel="noopener noreferrer">Live</a> |
                                <a href="https://github.com/nurulhudaapon/zx-example-portfolio" target="_blank"
                                    rel="noopener noreferrer">Source</a>
                            </li>
                        </ul>
                    </section>
                </main>
            </div>
        
            <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.30.0/components/prism-core.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.30.0/plugins/autoloader/prism-autoloader.min.js">
            </script>
            <script type="module">
                {[@embedFile("../../assets/doc.js"):s]}
            </script>
        </body>
        
        </html>
    );
}

fn ExampleBlock(allocator: zx.Allocator, props: ExampleBlockProps) zx.Component {
    return (
        <div class="code-example" @allocator={allocator}>
            <div class="example-code">
                <h4>ZX</h4>
                <pre><code id={zx_code_id} class="language-jsx" contenteditable="true" spellcheck="false" data-full-content={escaped_full_zx} data-truncated-content={truncated_zx_code} title="Click to view full code">{truncated_zx_code}</code></pre>
            </div>
            <div class="example-code">
                <input type="radio" id={preview_id} name={name_id} class="tab-radio" checked>
                <input type="radio" id={html_id} name={name_id} class="tab-radio">
                <input type="radio" id={zig_id} name={name_id} class="tab-radio">
                <div class="pane-header">
                    <div class="tab-buttons">
                        <label for={preview_id} class="tab-btn">Preview</label>
                        <label for={html_id} class="tab-btn">HTML</label>
                        <label for={zig_id} class="tab-btn">Zig</label>
                    </div>
                </div>
                <div class="tab-content" id={preview_content_id}>
                    <div class="preview-wrapper">
                        <iframe class="preview-frame" srcdoc={props.html_code}></iframe>
                    </div>
                </div>
                <div class="tab-content" id={html_content_id}>
                    <div class="code-wrapper">
                        <pre><code class="language-markup">{props.html_code}</code></pre>
                    </div>
                </div>
                <div class="tab-content" id={zig_content_id}>
                    <div class="code-wrapper">
                        <pre><code class="language-zig" data-full-content={escaped_full_zig} data-truncated-content={truncated_zig_code}>{truncated_zig_code}</code></pre>
                    </div>
                </div>
            </div>
        </div>
    );
}

const zx = @import("zx");
const std = @import("std");
const util = @import("util.zig");
`;

export const fmtCases = [
    {
        ins: [inIfBlock1, inIfBlock2, inIfBlock3, inIfBlock4, inIfBlock5, inIfBlock6, inIfBlock7, inIfBlock8, inIfBlock9, inIfBlock10],
        outIfBlock,
    },
    {
        ins: [inIfLiner1, inIfLiner2, inIfLiner3, inIfLiner4, inIfLiner5, inIfLiner6, inIfLiner7, inIfLiner8, inIfLiner9, inIfLiner10, inIfLiner11, inIfLiner12],
        outIfLiner,
    },
    {
        ins: [inSwitchBlock1, inSwitchBlock2, inSwitchBlock3, inSwitchBlock4, inSwitchBlock5, inSwitchBlock6, inSwitchBlock7],
        outSwitchBlock,
    },
    {
        ins: [inLargeMixexdContent],
        outLargeMixedContent,
    },
];
