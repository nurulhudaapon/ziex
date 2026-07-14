import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { hydrateAll } from "../../../pkg/ziex/src/jsx";

export function Counter(props: { visit_count: number }) {
    const [count, setCount] = useState(props.visit_count);

    return (
        <main>
            <button onClick={() => setCount(count + 1)}>Increment</button>
            <button onClick={() => setCount(count - 1)}>Decrement</button>
            <p>{count}</p>
        </main>
    );
}

const registry = {
    'Counter': () => Promise.resolve(Counter),
};

hydrateAll(registry, (el, C, props) => createRoot(el).render(React.createElement(C, props)));
