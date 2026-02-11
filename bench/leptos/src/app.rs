use leptos::prelude::*;
use leptos_meta::{provide_meta_context};
use leptos_router::{
    components::{Route, Router, Routes},
    StaticSegment,
};

#[component]
pub fn App() -> impl IntoView {
    provide_meta_context();

    view! {
        <Router>
            <Routes fallback=move || "Not found.">
                <Route path=StaticSegment("") view=HomePage/>
                <Route path=StaticSegment("ssr") view=SsrPage/>
            </Routes>
        </Router>
    }
}

/// Renders the SSR page of your application.
#[component]
fn SsrPage() -> impl IntoView {
    let items: Vec<u32> = (0..50).map(|_| 1).collect();

    view! {
        <main>
            {items
                .into_iter()
                .enumerate()
                .map(|(i, v)| {
                    view! { <div>"SSR " {v} "-" {i}</div> }
                })
                .collect_view()}
        </main>
    }
}

/// Renders the home page of your application.
#[component]
fn HomePage() -> impl IntoView {
    // Creates a reactive value to update the button
    let count = RwSignal::new(0);
    let on_click = move |_| *count.write() += 1;

    view! {
        <h1>"Welcome to Leptos!"</h1>
        <button on:click=on_click>"Click Me: " {count}</button>
    }
}