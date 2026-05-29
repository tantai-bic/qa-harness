# Module Creation Pattern

> Template cho tạo module mới (API 4 files | E2E 6 files).

## Module Creation Pattern

### API module (4 files)

```
src/<module>/
├── <module>.types.ts       # interface XPayload, XResponse, XEntity
├── <module>.factory.ts     # createXPayload(overrides?)
├── <module>.service.ts     # createX(request, token, overrides?, testName?)
└── index.ts                # export * + export as XService
```
Plus: add endpoints vào `src/constants/api.constants.ts`.

### E2E module (6 files)

```
src/<module>/
├── <module>.types.ts             # interface XViewModel (shape data UI hiển thị)
├── <module>.factory.ts           # createXViewModel(overrides?) — seed UI state
├── <module>.service.ts           # API setup giúp E2E (vd seedXViaApi)
├── pages/<module>.page.ts        # POM cho page chính của module
├── components/<x>.component.ts   # COM nếu có UI element reusable
└── index.ts                      # export *
```
Plus: add routes vào `src/constants/routes.constants.ts`, fixture vào `src/fixtures/<module>.fixture.ts`.

### Module creation checklist

```
☐ types.ts — interface đầy đủ, NO `any`
☐ factory.ts — faker unique ID, support overrides
☐ Endpoint / route đã thêm vào constants/
☐ service.ts — signature đúng (request, token, overrides?, testName?)
☐ (E2E) page.ts — locators readonly, getByRole ưu tiên
☐ (E2E) component.ts — tách nếu reuse ≥ 2 page
☐ fixture.ts — compose với existing fixture (auth, ...)
☐ index.ts — re-export public surface
☐ Đã chạy `tsc --noEmit` — không lỗi
```
