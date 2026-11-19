export function saleFee(tier, amount) { return tier === 'kyc2' ? amount * .05 + 1.80 : amount * .08 + 2.50; }
export function withdrawalFee(tier, amount) { return tier === 'kyc2' ? amount * .05 + 1 : amount * .09; }
export function providerFor(profile) { return profile.kyc_tier === 'kyc2' && profile.kyc_status === 'approved' ? 'mistic' : 'lunar'; }

