MoistureClampEnvironments = {
    DRY = 1,
    NORMAL = 2,
    WET = 3
}

MoistureClamp = {
    Environments = {
        [MoistureClampEnvironments.DRY] = {
            Months = {
                -- January: Winter - high moisture (cold, slow evaporation)
                [1] = {
                    Min = 8,
                    Max = 20
                },
                -- February: Late winter - high moisture
                [2] = {
                    Min = 7,
                    Max = 19
                },
                -- March: Early spring - moderate-high moisture
                [3] = {
                    Min = 6,
                    Max = 17
                },
                -- April: Spring - moderate moisture
                [4] = {
                    Min = 5,
                    Max = 15
                },
                -- May: Late spring - moderate moisture
                [5] = {
                    Min = 4,
                    Max = 13
                },
                -- June: Early summer - lower moisture (warm, drying)
                [6] = {
                    Min = 3,
                    Max = 11
                },
                -- July: Peak summer - lowest moisture (hot, peak drying)
                [7] = {
                    Min = 2,
                    Max = 10
                },
                -- August: Late summer - low moisture (still hot)
                [8] = {
                    Min = 3,
                    Max = 11
                },
                -- September: Early fall - moderate moisture
                [9] = {
                    Min = 4,
                    Max = 13
                },
                -- October: Fall - moderate-high moisture
                [10] = {
                    Min = 5,
                    Max = 15
                },
                -- November: Late fall - high moisture (cooling, autumn rains)
                [11] = {
                    Min = 7,
                    Max = 18
                },
                -- December: Early winter - high moisture (cold, rain/snow)
                [12] = {
                    Min = 8,
                    Max = 20
                }
            }
        },
        [MoistureClampEnvironments.NORMAL] = {
            Months = {
                -- January: Winter - high moisture (cold, slow evaporation)
                [1] = {
                    Min = 12,
                    Max = 28
                },
                -- February: Late winter - high moisture
                [2] = {
                    Min = 11,
                    Max = 26
                },
                -- March: Early spring - moderate-high moisture
                [3] = {
                    Min = 9,
                    Max = 23
                },
                -- April: Spring - moderate moisture
                [4] = {
                    Min = 7,
                    Max = 20
                },
                -- May: Late spring - moderate moisture
                [5] = {
                    Min = 6,
                    Max = 18
                },
                -- June: Early summer - lower moisture (warm, drying)
                [6] = {
                    Min = 5,
                    Max = 16
                },
                -- July: Peak summer - lowest moisture (hot, peak drying)
                [7] = {
                    Min = 4,
                    Max = 14
                },
                -- August: Late summer - low moisture (baseline: 6-18%)
                [8] = {
                    Min = 6,
                    Max = 18
                },
                -- September: Early fall - moderate moisture
                [9] = {
                    Min = 7,
                    Max = 20
                },
                -- October: Fall - moderate-high moisture
                [10] = {
                    Min = 9,
                    Max = 23
                },
                -- November: Late fall - high moisture (cooling, autumn rains)
                [11] = {
                    Min = 11,
                    Max = 26
                },
                -- December: Early winter - high moisture (cold, rain/snow)
                [12] = {
                    Min = 12,
                    Max = 28
                }
            }
        },
        [MoistureClampEnvironments.WET] = {
            Months = {
                -- January: Winter - very high moisture (cold, slow evaporation)
                [1] = {
                    Min = 18,
                    Max = 38
                },
                -- February: Late winter - very high moisture
                [2] = {
                    Min = 17,
                    Max = 36
                },
                -- March: Early spring - high moisture
                [3] = {
                    Min = 14,
                    Max = 32
                },
                -- April: Spring - moderate-high moisture
                [4] = {
                    Min = 11,
                    Max = 28
                },
                -- May: Late spring - moderate-high moisture
                [5] = {
                    Min = 9,
                    Max = 24
                },
                -- June: Early summer - moderate moisture
                [6] = {
                    Min = 8,
                    Max = 22
                },
                -- July: Peak summer - lower moisture (still wet environment)
                [7] = {
                    Min = 7,
                    Max = 20
                },
                -- August: Late summer - moderate moisture
                [8] = {
                    Min = 8,
                    Max = 22
                },
                -- September: Early fall - moderate-high moisture
                [9] = {
                    Min = 11,
                    Max = 28
                },
                -- October: Fall - high moisture
                [10] = {
                    Min = 14,
                    Max = 32
                },
                -- November: Late fall - very high moisture (cooling, heavy rains)
                [11] = {
                    Min = 17,
                    Max = 36
                },
                -- December: Early winter - very high moisture (cold, rain/snow)
                [12] = {
                    Min = 18,
                    Max = 38
                }
            }
        }
    }
}
