# Adding the Allure reporter to `playwright.config.ts`

Add `allure-playwright` to the reporter list, keeping the existing reporters.
The site `parentSuite` label is injected by the `push-allure-results` action
afterwards, so **nothing needs to change in the spec files**.

```ts
// playwright.config.ts
export default defineConfig({
  // ...
  reporter: [
    ['list'],
    ['html', { open: 'never' }],
    ['allure-playwright', { resultsDir: 'allure-results' }],
  ],
});
```

Then:

```bash
# npm repo (yoga)
npm i -D allure-playwright
# pnpm repo (danse/billetterie)
pnpm add -D allure-playwright
```

Keep attachments lean to avoid bloating the Pi store — record traces/videos only
on failure (already the case in both repos):

```ts
use: { trace: 'on-first-retry', video: 'retain-on-failure' },
```
