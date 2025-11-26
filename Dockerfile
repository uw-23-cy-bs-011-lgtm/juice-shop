/*
 * Copyright (c) 2014-2026 Bjoern Kimminich & the OWASP Juice Shop contributors.
 * SPDX-License-Identifier: MIT
 */
import type { BasketItemModel } from 'models/basketitem'
import type { ChallengeKey, ChallengeModel } from 'models/challenge'
import type { ComplaintModel } from 'models/complaint'
import type { FeedbackModel } from 'models/feedback'
import type { ProductModel } from 'models/product'
import type { BasketModel } from 'models/basket'
import type { UserModel } from 'models/user'

/* jslint node: true */
export const challenges: Record<ChallengeKey, ChallengeModel> = {} as Record<ChallengeKey, ChallengeModel>
export const users: Record<string, UserModel> = {}
export const products: Record<string, ProductModel> = {}
export const feedback: Record<string, FeedbackModel> = {}
export const baskets: Record<string, BasketModel> = {}
export const basketItems: Record<string, BasketItemModel> = {}
export const complaints: Record<string, ComplaintModel> = {}

export interface Notification {
  key: string
  name: string
  challenge: string
  flag: string
  hidden: boolean
  isRestore: boolean
}
export const notifications: Notification[] = []

// ✅ Secure encapsulation: private variable, controlled access
let _retrieveBlueprintChallengeFile: string | null = null

export function getRetrieveBlueprintChallengeFile (): string | null {
  return _retrieveBlueprintChallengeFile
}

export function setRetrieveBlueprintChallengeFile (retrieveBlueprintChallengeFileArg: string): void {
  _retrieveBlueprintChallengeFile = retrieveBlueprintChallengeFileArg
}
