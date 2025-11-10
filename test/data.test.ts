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


const outSwitchBlock =`pub fn Page(allocator: zx.Allocator) zx.Component {
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

export const fmtCases = [
  {
    ins: [inIfBlock1],
    outIfBlock,
  },
  {
    ins: [inIfLiner1, inIfLiner2],
    outIfLiner,
  },
  {
    ins: [inSwitchBlock1],
    outSwitchBlock,
  },
];
