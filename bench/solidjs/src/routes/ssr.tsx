import { For } from "solid-js"

export default function Ssr() {
    const arr = Array.from({ length: 50 }, () => 1);

    return (
        <main>
            <For each={arr}>
                {(v, i) =>
                    <div>SSR {v}-{i()}</div>
                }
            </For>
        </main>
    );
}

// Prevent static optimization
export const prerender = false;