import type { ComponentMetadata } from "./types";

export type PreparedComponent = {
  domNode: HTMLElement;
  props: Record<string, any> & {
    dangerouslySetInnerHTML?: { __html: string };
  };
  Component: (props: any) => React.ReactElement;
};

function findCommentMarker(id: string): { 
  startComment: Comment; 
  endComment: Comment;
  name: string;
  props: Record<string, any>;
} | null {
  const startPrefix = `$${id} `;
  const endMarker = `/$${id}`;
  
  const walker = document.createTreeWalker(
    document.body,
    NodeFilter.SHOW_COMMENT,
    null
  );
  
  let startComment: Comment | null = null;
  let endComment: Comment | null = null;
  let name = "";
  let props: Record<string, any> = {};
  
  let node: Comment | null;
  while ((node = walker.nextNode() as Comment | null)) {
    const text = node.textContent?.trim() || "";
    
    if (text.startsWith(startPrefix)) {
      startComment = node;
      
      const content = text.slice(startPrefix.length);
      const jsonStart = content.indexOf("{");
      
      if (jsonStart !== -1) {
        name = content.slice(0, jsonStart).trim();
        const jsonStr = content.slice(jsonStart);
        try {
          props = JSON.parse(jsonStr);
        } catch {
        }
      } else {
        name = content.trim();
      }
    }
    
    if (text === endMarker) {
      endComment = node;
      break;
    }
  }
  
  if (startComment && endComment) {
    return { startComment, endComment, name, props };
  }
  
  return null;
}

function createContainerBetweenMarkers(startComment: Comment, endComment: Comment): HTMLElement {
  const container = document.createElement("div");
  container.style.display = "contents";
  
  let current = startComment.nextSibling;
  while (current && current !== endComment) {
    const next = current.nextSibling;
    container.appendChild(current);
    current = next;
  }
  
  endComment.parentNode?.insertBefore(container, endComment);
  
  return container;
}

export async function prepareComponent(component: ComponentMetadata): Promise<PreparedComponent> {
  const marker = findCommentMarker(component.id);
  if (!marker) {
    throw new Error(`Comment marker for ${component.id} not found`, { cause: component });
  }

  const props = marker.props;
  
  const domNode = createContainerBetweenMarkers(marker.startComment, marker.endComment);

  const Component = await component.import();
  return { domNode, props, Component };
}

export function filterComponents(components: ComponentMetadata[]): ComponentMetadata[] {
  const currentPath = window.location.pathname;
  return components.filter((component) => component.route === currentPath || !component.route);
}

export type DiscoveredComponent = {
  id: string;
  name: string;
  props: Record<string, any>;
  container: HTMLElement;
};

export function discoverComponents(): DiscoveredComponent[] {
  const components: DiscoveredComponent[] = [];
  
  const walker = document.createTreeWalker(
    document.body,
    NodeFilter.SHOW_COMMENT,
    null
  );
  
  const markers: Array<{
    id: string;
    name: string;
    props: Record<string, any>;
    startComment: Comment;
    endComment: Comment | null;
  }> = [];
  
  let node: Comment | null;
  while ((node = walker.nextNode() as Comment | null)) {
    const text = node.textContent?.trim() || "";
    if (text.startsWith("$") && !text.startsWith("/$")) {
      const spaceIdx = text.indexOf(" ");
      if (spaceIdx !== -1) {
        const id = text.slice(1, spaceIdx);
        const content = text.slice(spaceIdx + 1);
        
        if (content.startsWith("[")) {
          continue;
        }
        
        const jsonStart = content.indexOf("{");
        
        let name = "";
        let props: Record<string, any> = {};
        
        if (jsonStart !== -1) {
          name = content.slice(0, jsonStart).trim();
          try {
            props = JSON.parse(content.slice(jsonStart));
          } catch {
          }
        } else {
          name = content.trim();
        }
        
        markers.push({ id, name, props, startComment: node, endComment: null });
      }
    }
    else if (text.startsWith("/$")) {
      const id = text.slice(2);
      const marker = markers.find(m => m.id === id && !m.endComment);
      if (marker) {
        marker.endComment = node;
      }
    }
  }
  
  for (const marker of markers) {
    if (!marker.endComment) continue;
    
    const container = createContainerBetweenMarkers(marker.startComment, marker.endComment);
    
    components.push({ 
      id: marker.id, 
      name: marker.name, 
      props: marker.props, 
      container 
    });
  }
  
  return components;
}

export type ComponentRegistry = Record<string, () => Promise<(props: any) => React.ReactElement>>;

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
