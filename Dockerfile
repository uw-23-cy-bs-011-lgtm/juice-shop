FROM node:22 AS builder
WORKDIR /juice-shop
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm dedupe --omit=dev && npm cache clean --force
COPY . .
RUN npm install -g typescript@5.6.3 ts-node@10.9.2
ARG CYCLONEDX_NPM_VERSION="0.5.2"
RUN npm install -g "@cyclonedx/cyclonedx-npm@${CYCLONEDX_NPM_VERSION}" && npm run sbom
FROM gcr.io/distroless/nodejs22-debian12
WORKDIR /juice-shop
COPY --from=builder --chown=65532:0 /juice-shop .
USER 65532
EXPOSE 3000
CMD ["/juice-shop/build/app.js"]
let _retrieveBlueprintChallengeFile: string | null = null

export function getRetrieveBlueprintChallengeFile (): string | null {
  return _retrieveBlueprintChallengeFile
}
export function setRetrieveBlueprintChallengeFile (arg: string): void {
  _retrieveBlueprintChallengeFile = arg
}
<button
  type="submit"
  id="changeButton"
  mat-raised-button
  [disabled]="passwordControl.invalid || newPasswordControl.invalid || repeatNewPasswordControl.invalid"
  color="primary"
  (click)="changePassword()"
>
  <i class="far fa-edit fa-lg" aria-hidden="true"></i>
  {{ 'BTN_CHANGE' | translate }}
</button>



