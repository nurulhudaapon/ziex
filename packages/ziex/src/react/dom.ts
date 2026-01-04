import type { ComponentMetadata } from "./types";

/**
 * Result of preparing a component for hydration.
 * 
 * Contains all the necessary data to render a React component into its server-rendered container.
 */
export type PreparedComponent = {
  /**
   * The HTML element where the component should be rendered.
   * 
   * This is a container element created between the comment markers. The server-rendered
   * content is moved into this container, and React will hydrate it with the interactive component.
   * 
   * @example
   * ```tsx
   * // Server-rendered HTML with comment markers:
   * // <!--$zx-abc123-0 CounterComponent {"max_count":10}-->
   * // <button>0</button>
   * // <!--/$zx-abc123-0-->
   * 
   * const { domNode } = await prepareComponent(component);
   * createRoot(domNode).render(<Component {...props} />);
   * ```
   */
  domNode: HTMLElement;
  
  /**
   * Component props parsed from the comment marker.
   * 
   * Props are extracted from the start comment marker content. The comment format is:
   * `<!--$id name props-->` where props is JSON-encoded.
   * 
   * @example
   * ```tsx
   * // Server-rendered HTML:
   * // <!--$zx-abc123-0 CounterComponent {"max_count":10,"label":"Counter"}-->
   * // <button>0</button>
   * // <!--/$zx-abc123-0-->
   * 
   * const { props } = await prepareComponent(component);
   * // props = { max_count: 10, label: "Counter" }
   * ```
   */
  props: Record<string, any> & {
    /**
     * React's special prop for setting inner HTML directly.
     * 
     * May be used when the component has server-rendered children that should
     * be preserved during hydration.
     */
    dangerouslySetInnerHTML?: { __html: string };
  };
  
  /**
   * The loaded React component function ready to render.
   * 
   * This is the default export from the component module, lazy-loaded via the component's
   * import function. The component is ready to be rendered with React's `createRoot().render()`.
   * 
   * @example
   * ```tsx
   * const { Component, props, domNode } = await prepareComponent(component);
   * 
   * // Component is the default export from the component file:
   * // export default function CounterComponent({ max_count }: { max_count: number }) {
   * //   return <div>Count: {max_count}</div>;
   * // }
   * 
   * createRoot(domNode).render(<Component {...props} />);
   * ```
   */
  Component: (props: any) => React.ReactElement;
};

/**
 * Finds a comment marker in the DOM by its ID.
 * 
 * Searches for comment nodes matching the format `<!--$id-->` where `id` is the component ID.
 * 
 * @param id - The component ID to search for (e.g., "zx-abc123-0")
 * @returns The start and end comment nodes, or null if not found
 */
function findCommentMarker(id: string): { 
  startComment: Comment; 
  endComment: Comment;
} | null {
  const startMarker = `$${id}`;
  const endMarker = `/$${id}`;
  
  // Use TreeWalker to efficiently find comment nodes
  const walker = document.createTreeWalker(
    document.body,
    NodeFilter.SHOW_COMMENT,
    null
  );
  
  let startComment: Comment | null = null;
  let endComment: Comment | null = null;
  
  let node: Comment | null;
  while ((node = walker.nextNode() as Comment | null)) {
    const text = node.textContent?.trim() || "";
    
    // Check for start marker: $id
    if (text === startMarker) {
      startComment = node;
    }
    
    // Check for end marker: /$id
    if (text === endMarker) {
      endComment = node;
      break;
    }
  }
  
  if (startComment && endComment) {
    return { startComment, endComment };
  }
  
  return null;
}

/**
 * Gets component metadata from the companion script element.
 * 
 * Searches for a script element with `data-zx="id"` attribute that contains
 * the component's name and props as JSON.
 * 
 * @param id - The component ID
 * @returns Parsed metadata with name and props, or default values if not found
 */
function getComponentMetadata(id: string): { name: string; props: Record<string, any> } {
  const script = document.querySelector(`script[data-zx="${id}"]`);
  if (script?.textContent) {
    try {
      const data = JSON.parse(script.textContent);
      return { name: data.name || "", props: data.props || {} };
    } catch {
      // Ignore parse errors
    }
  }
  return { name: "", props: {} };
}

/**
 * Creates a container element for React to render into, positioned between the comment markers.
 * 
 * @param startComment - The start comment marker
 * @param endComment - The end comment marker  
 * @returns A new container element inserted between the markers
 */
function createContainerBetweenMarkers(startComment: Comment, endComment: Comment): HTMLElement {
  const container = document.createElement("div");
  container.style.display = "contents"; // Invisible wrapper
  
  // Move all nodes between start and end into the container
  let current = startComment.nextSibling;
  while (current && current !== endComment) {
    const next = current.nextSibling;
    container.appendChild(current);
    current = next;
  }
  
  // Insert container before end marker
  endComment.parentNode?.insertBefore(container, endComment);
  
  return container;
}

/**
 * Prepares a client-side component for hydration by locating its comment markers, extracting
 * props from the marker content, and lazy-loading the component module.
 * 
 * This function bridges server-rendered HTML (from ZX's Zig transpiler) and client-side React
 * components. It searches for comment markers in the format `<!--$id name props-->...<!--/$id-->`
 * and extracts the component data from the marker content.
 * 
 * @param component - The component metadata containing ID, import function, and other metadata
 *                    needed to locate and load the component
 * 
 * @returns A Promise that resolves to a `PreparedComponent` object containing the DOM node,
 *          parsed props, and the loaded React component function
 * 
 * @throws {Error} If the component's comment markers cannot be found in the DOM. This typically
 *                 happens if the component ID doesn't match any marker, the script runs before
 *                 the HTML is loaded, or there's a mismatch between server and client metadata
 * 
 * @example
 * ```tsx
 * // Basic usage with React:
 * import { createRoot } from "react-dom/client";
 * import { prepareComponent } from "ziex";
 * import { components } from "@ziex/components";
 * 
 * for (const component of components) {
 *   prepareComponent(component).then(({ domNode, Component, props }) => {
 *     createRoot(domNode).render(<Component {...props} />);
 *   }).catch(console.error);
 * }
 * ```
 * 
 * @example
 * ```tsx
 * // Server-rendered HTML with comment markers:
 * // <!--$zx-abc123-0 CounterComponent {"max_count":10}-->
 * // <button>0</button>
 * // <!--/$zx-abc123-0-->
 * ```
 */
export async function prepareComponent(component: ComponentMetadata): Promise<PreparedComponent> {
  const marker = findCommentMarker(component.id);
  if (!marker) {
    throw new Error(`Comment marker for ${component.id} not found`, { cause: component });
  }

  // Get props from the companion script element
  const metadata = getComponentMetadata(component.id);
  const props = metadata.props;
  
  // Create a container for React to render into
  const domNode = createContainerBetweenMarkers(marker.startComment, marker.endComment);

  const Component = await component.import();
  return { domNode, props, Component };
}

export function filterComponents(components: ComponentMetadata[]): ComponentMetadata[] {
  const currentPath = window.location.pathname;
  return components.filter((component) => component.route === currentPath || !component.route);
}

/**
 * Discovered component from DOM traversal.
 * Contains all metadata needed to hydrate the component.
 */
export type DiscoveredComponent = {
  id: string;
  name: string;
  props: Record<string, any>;
  container: HTMLElement;
};

/**
 * Finds all React component markers in the DOM and returns their metadata.
 * 
 * This is a DOM-first approach that:
 * 1. Walks the DOM once to find all `<!--$id-->` markers
 * 2. Reads metadata from companion `<script data-zx="id">` elements
 * 3. Creates containers for React to render into
 * 
 * @returns Array of discovered components with their containers and props
 */
export function discoverComponents(): DiscoveredComponent[] {
  const components: DiscoveredComponent[] = [];
  
  // Find all metadata scripts
  const scripts = Array.from(document.querySelectorAll<HTMLScriptElement>('script[data-zx]'));
  
  for (const script of scripts) {
    const id = script.getAttribute('data-zx');
    if (!id) continue;
    
    // Parse metadata
    let name = "";
    let props: Record<string, any> = {};
    try {
      const data = JSON.parse(script.textContent || "{}");
      name = data.name || "";
      props = data.props || {};
    } catch {
      continue;
    }
    
    // Find the comment markers
    const marker = findCommentMarker(id);
    if (!marker) continue;
    
    // Create container
    const container = createContainerBetweenMarkers(marker.startComment, marker.endComment);
    
    components.push({ id, name, props, container });
  }
  
  return components;
}

/**
 * Component registry mapping component names to their import functions.
 */
export type ComponentRegistry = Record<string, () => Promise<(props: any) => React.ReactElement>>;

/**
 * Hydrates all React components found in the DOM.
 * 
 * This is the simplest way to hydrate React islands - it automatically:
 * 1. Discovers all component markers in the DOM
 * 2. Looks up components by name in the registry
 * 3. Renders each component into its container
 * 
 * @param registry - Map of component names to import functions
 * @param render - Function to render a component (e.g., `(el, Component, props) => createRoot(el).render(<Component {...props} />)`)
 * 
 * @example
 * ```ts
 * import { hydrateAll } from "ziex/react";
 * 
 * hydrateAll({
 *   CounterComponent: () => import("./Counter"),
 *   ToggleComponent: () => import("./Toggle"),
 * });
 * ```
 */
export async function hydrateAll(
  registry: ComponentRegistry,
  render: (container: HTMLElement, Component: (props: any) => React.ReactElement, props: Record<string, any>) => void
): Promise<void> {
  const components = discoverComponents();
  
  await Promise.all(components.map(async ({ name, props, container }) => {
    const importer = registry[name];
    if (!importer) {
      console.warn(`Component "${name}" not found in registry`);
      return;
    }
    
    try {
      const Component = await importer();
      render(container, Component, props);
    } catch (error) {
      console.error(`Failed to hydrate "${name}":`, error);
    }
  }));
}