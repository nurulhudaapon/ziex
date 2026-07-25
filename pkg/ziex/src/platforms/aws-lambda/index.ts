/**
 * Ziex adapter for AWS Lambda (API Gateway v1, v2, and ALB).
 *
 * Based on Hono's AWS Lambda adapter implementation.
 *
 * @example API Gateway v2 (HTTP API)
 * ```ts
 * import { Ziex } from "ziex/cloudflare";
 * import { handle } from "ziex/aws-lambda";
 * import module from "./app.wasm";
 *
 * const app = new Ziex({ module });
 * export const handler = handle(app);
 * ```
 */

// ---------------------------------------------------------------------------
// Minimal Lambda event / context types (avoids requiring @types/aws-lambda)
// ---------------------------------------------------------------------------

type ApiGwV1Event = {
    version?: "1.0";
    httpMethod: string;
    path: string;
    headers: Record<string, string> | null;
    multiValueHeaders: Record<string, string[]> | null;
    queryStringParameters: Record<string, string> | null;
    multiValueQueryStringParameters: Record<string, string[]> | null;
    body: string | null;
    isBase64Encoded: boolean;
    requestContext: { elb?: unknown };
};

type ApiGwV2Event = {
    version: "2.0";
    requestContext: { http: { method: string } };
    rawPath: string;
    rawQueryString: string;
    headers: Record<string, string>;
    body?: string;
    isBase64Encoded: boolean;
};

type AlbEvent = {
    httpMethod: string;
    path: string;
    headers: Record<string, string> | null;
    multiValueHeaders: Record<string, string[]> | null;
    queryStringParameters: Record<string, string> | null;
    multiValueQueryStringParameters: Record<string, string[]> | null;
    body: string | null;
    isBase64Encoded: boolean;
    requestContext: { elb: unknown };
};

export type LambdaEvent = ApiGwV1Event | ApiGwV2Event | AlbEvent;

export type LambdaContext = {
    functionName: string;
    functionVersion: string;
    invokedFunctionArn: string;
    memoryLimitInMB: string;
    awsRequestId: string;
    logGroupName: string;
    logStreamName: string;
    callbackWaitsForEmptyEventLoop: boolean;
    getRemainingTimeInMillis(): number;
};

export type LambdaResult = {
    statusCode: number;
    headers: Record<string, string>;
    multiValueHeaders: Record<string, string[]>;
    body: string;
    isBase64Encoded: boolean;
    cookies?: string[];
};

// ---------------------------------------------------------------------------
// Event detection
// ---------------------------------------------------------------------------

function isV2(event: LambdaEvent): event is ApiGwV2Event {
    return (
        "requestContext" in event &&
        event.requestContext !== null &&
        "http" in (event.requestContext as object)
    );
}

function isAlb(event: LambdaEvent): event is AlbEvent {
    return (
        "requestContext" in event &&
        event.requestContext !== null &&
        "elb" in (event.requestContext as object)
    );
}

// ---------------------------------------------------------------------------
// Event → Request
// ---------------------------------------------------------------------------

function getMethod(event: LambdaEvent): string {
    if (isV2(event)) return event.requestContext.http.method;
    return (event as ApiGwV1Event | AlbEvent).httpMethod;
}

function getPath(event: LambdaEvent): string {
    if (isV2(event)) {
        return event.rawPath + (event.rawQueryString ? `?${event.rawQueryString}` : "");
    }
    const e = event as ApiGwV1Event | AlbEvent;
    const mvqs = e.multiValueQueryStringParameters;
    const qs = e.queryStringParameters;

    let queryString = "";
    if (mvqs) {
        queryString = Object.entries(mvqs)
            .flatMap(([k, vs]) => (vs ?? []).map((v) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`))
            .join("&");
    } else if (qs) {
        queryString = new URLSearchParams(qs).toString();
    }
    return e.path + (queryString ? `?${queryString}` : "");
}

function getHeaders(event: LambdaEvent): Headers {
    const headers = new Headers();
    if (event.headers) {
        for (const [k, v] of Object.entries(event.headers)) {
            if (v != null) headers.set(k, v);
        }
    }
    // Multi-value headers override single-value (more precise)
    if ("multiValueHeaders" in event && event.multiValueHeaders) {
        for (const [k, vs] of Object.entries(event.multiValueHeaders)) {
            if (!vs?.length) continue;
            headers.delete(k);
            for (const v of vs) headers.append(k, v);
        }
    }
    return headers;
}

function decodeBase64(base64: string): Uint8Array {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
}

function encodeBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]!);
    return btoa(binary);
}

function getBody(event: LambdaEvent): BodyInit | null {
    if (!event.body) return null;
    if (event.isBase64Encoded) return decodeBase64(event.body) as BodyInit;
    return event.body;
}

function toRequest(event: LambdaEvent, headers: Headers): Request {
    const method = getMethod(event);
    const host = headers.get("host") ?? "localhost";
    const proto = headers.get("x-forwarded-proto") ?? "https";
    const path = getPath(event);
    const url = `${proto}://${host}${path}`;
    const body = ["GET", "HEAD"].includes(method) ? null : getBody(event);
    return new Request(url, { method, headers, body });
}

// ---------------------------------------------------------------------------
// Response → Lambda result
// ---------------------------------------------------------------------------

const TEXT_CONTENT_TYPES = [
    "text/",
    "application/json",
    "application/xml",
    "application/javascript",
    "application/xhtml",
];

function isBinaryContent(contentType: string, binaryMediaTypes: string[]): boolean {
    if (binaryMediaTypes.length > 0) {
        return binaryMediaTypes.some((t) => contentType.includes(t));
    }
    return !TEXT_CONTENT_TYPES.some((t) => contentType.startsWith(t));
}

async function toLambdaResult(
    res: Response,
    binaryMediaTypes: string[],
): Promise<LambdaResult> {
    const responseHeaders: Record<string, string> = {};
    const multiValueHeaders: Record<string, string[]> = {};

    res.headers.forEach((value, key) => {
        if (key in responseHeaders) {
            multiValueHeaders[key] = [...(multiValueHeaders[key] ?? [responseHeaders[key]]), value];
            delete responseHeaders[key];
        } else if (key in multiValueHeaders) {
            multiValueHeaders[key].push(value);
        } else {
            responseHeaders[key] = value;
        }
    });

    const contentType = res.headers.get("content-type") ?? "";
    const binary = isBinaryContent(contentType, binaryMediaTypes);

    let body: string;
    let isBase64Encoded = false;
    if (binary) {
        body = encodeBase64(await res.arrayBuffer());
        isBase64Encoded = true;
    } else {
        body = await res.text();
    }

    return {
        statusCode: res.status,
        headers: responseHeaders,
        multiValueHeaders,
        body,
        isBase64Encoded,
    };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

type FetchApp = { fetch(req: Request, env?: unknown, ctx?: unknown): Promise<Response> };

export type HandleOptions = {
    /**
     * Content types to encode as base64 in the Lambda response.
     * By default, non-text content types are base64 encoded automatically.
     */
    binaryMediaTypes?: string[];
};

/**
 * Wrap a Ziex app as an AWS Lambda handler.
 *
 * @example
 * ```ts
 * import { handle } from "ziex/aws-lambda";
 * export const handler = handle(app);
 * ```
 */
export function handle(app: FetchApp, options: HandleOptions = {}) {
    const binaryMediaTypes = options.binaryMediaTypes ?? [];
    return async (event: LambdaEvent, _context?: LambdaContext): Promise<LambdaResult> => {
        const headers = getHeaders(event);
        const req = toRequest(event, headers);
        const res = await app.fetch(req);
        return toLambdaResult(res, binaryMediaTypes);
    };
}
