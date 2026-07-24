import { test, expect } from '@playwright/test';
import { skipOnRemoteStatic } from '../../helpers/env';

test.describe('API Route Examples', () => {
  test('GET /examples/api-route returns method and path json', async ({ request }) => {
    const res = await request.get('/examples/api-route');
    expect(res.ok()).toBeTruthy();
    await expect(res).toBeOK();
    const body = await res.json();
    expect(body).toEqual({
      method: 'GET',
      path: '/examples/api-route',
    });
  });

  test('POST /examples/api-route creates a user from json body', async ({ request }) => {
    test.skip(skipOnRemoteStatic, 'Static deploy has no live POST API handlers');
    const res = await request.post('/examples/api-route', {
      data: { name: 'E2E Alice' },
    });
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body).toMatchObject({
      id: 1,
      name: 'E2E Alice',
      status: 'created',
    });
  });

  test('POST /examples/api-route without name returns validation message', async ({ request }) => {
    test.skip(skipOnRemoteStatic, 'Static deploy has no live POST API handlers');
    const res = await request.post('/examples/api-route', {
      data: {},
    });
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body).toMatchObject({
      message: '`name` field is required',
    });
  });

  test('GET /examples/api-route/check responds successfully', async ({ request }) => {
    const res = await request.get('/examples/api-route/check');
    expect(res.status()).toBe(200);
  });
});
