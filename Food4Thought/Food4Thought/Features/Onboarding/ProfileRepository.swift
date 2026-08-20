import Foundation
import Food4ThoughtCore
import Supabase

/// Whether a timezone sync actually moved the stored value.
///
/// The distinction matters to the caller: a moved zone moves every day boundary
/// the balance rollup was built on, so the rollup has to be rebuilt.
enum TimeZoneSyncResult: Equatable, Sendable {
    case unchanged
    case updated
}

/// The answers the questionnaire gathered, as they stand now.
///
/// Everything needed to re-open that questionnaire from Settings and rewrite
/// it — which is the same call, since `complete_onboarding` supersedes the
/// goal set rather than refusing a second run.
struct ProfileDetails: Equatable, Sendable {
    let displayName: String?
    let birthDate: Date
    let sex: BiologicalSex
    let heightCm: Double
    let activityLevel: ActivityLevel
    let goal: GoalType
    let mealSchedule: MealSchedule
}

/// The plan currently in force, in the terms the weight projection needs.
///
/// `effectiveFrom` matters as much as the numbers: it is the day this plan
/// started, and projecting from before it would draw a line the user never
/// agreed to over days they were following different targets.
struct GoalSetSummary: Equatable, Sendable {
    let dailyCalorieTarget: Int
    let totalDailyEnergyExpenditure: Double
    let goal: GoalType
    let effectiveFrom: Date

    /// Target minus TDEE: negative on a deficit, positive on a surplus.
    var dailyKcalDelta: Double {
        Double(dailyCalorieTarget) - totalDailyEnergyExpenditure
    }
}

protocol ProfileRepository: Sendable {
    /// Drives routing: a signed-in user without this set goes to onboarding.
    func hasCompletedOnboarding(userID: UUID) async throws -> Bool

    /// The open goal set, for drawing the plan against actual weight.
    func activeGoalSet(userID: UUID) async throws -> GoalSetSummary?

    /// What Settings shows when someone opens their own details.
    ///
    /// Nil when the profile predates onboarding or has no active goal set —
    /// there is nothing to edit yet, and inventing defaults would let someone
    /// "save" a plan built from figures they never gave.
    func currentDetails(userID: UUID) async throws -> ProfileDetails?

    /// Persists the whole questionnaire in one transaction. Partial success is
    /// the failure mode worth avoiding here — a profile without a goal set
    /// routes past onboarding to a dashboard that has no targets to show.
    func completeOnboarding(_ submission: OnboardingSubmission) async throws

    /// Stores the device's IANA timezone, e.g. "Europe/Lisbon".
    ///
    /// `profiles.time_zone` defaults to UTC, and every day boundary in the
    /// balance rollup is cut in that zone. Left unwritten, a user five hours off
    /// UTC has their evening meals scored against the following day — which
    /// reads as a balance bug, not a timezone one. Cheap enough to reconcile on
    /// every launch, and travel is precisely when it changes.
    func syncTimeZone(_ identifier: String, userID: UUID) async throws -> TimeZoneSyncResult

    /// The user's meal slots **as they stand today**. Every log has to land in
    /// one of them, and the centre + button infers which without asking.
    ///
    /// One-day meals are filtered out here rather than at each call site: a
    /// caller that forgot would keep offering yesterday's birthday cake, and
    /// the shares would no longer sum to 1 so the pace pill would drift too.
    func mealSchedule(userID: UUID) async throws -> MealSchedule

    /// Replaces the stored schedule. Used by adding and removing a meal.
    ///
    /// Takes the whole schedule rather than a delta because the shares are
    /// normalised across all slots — changing one changes every other.
    func updateMealSchedule(_ schedule: MealSchedule, userID: UUID) async throws

    #if DEBUG
    /// Development-only: clears the routing flag so the questionnaire can be
    /// re-run without editing the database by hand. Deliberately leaves goal
    /// and weight history alone — re-completing supersedes them the same way a
    /// real goal edit would. Delete once Settings can edit goals properly.
    func resetOnboarding(userID: UUID) async throws
    #endif
}

struct SupabaseProfileRepository: ProfileRepository {
    private struct OnboardingStatusRow: Decodable {
        let onboardingCompletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case onboardingCompletedAt = "onboarding_completed_at"
        }
    }

    /// Mirrors the argument names of public.complete_onboarding.
    private struct CompleteOnboardingParams: Encodable {
        let birthDate: String
        let biologicalSex: String
        let heightCm: Double
        let weightKg: Double
        let mealSchedule: MealSchedule
        let goalType: String
        let activityLevel: String
        let bmr: Double
        let tdee: Double
        let bmi: Double
        let dailyCalorieTarget: Int
        let proteinGTarget: Double
        let carbsGTarget: Double
        let fatGTarget: Double
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case birthDate = "p_birth_date"
            case biologicalSex = "p_biological_sex"
            case heightCm = "p_height_cm"
            case weightKg = "p_weight_kg"
            case mealSchedule = "p_meal_schedule"
            case goalType = "p_goal_type"
            case activityLevel = "p_activity_level"
            case bmr = "p_bmr"
            case tdee = "p_tdee"
            case bmi = "p_bmi"
            case dailyCalorieTarget = "p_daily_calorie_target"
            case proteinGTarget = "p_protein_g_target"
            case carbsGTarget = "p_carbs_g_target"
            case fatGTarget = "p_fat_g_target"
            case displayName = "p_display_name"
        }
    }

    private let client: SupabaseClient
    private let calendar: Calendar

    init(client: SupabaseClient = SupabaseClientProvider.shared, calendar: Calendar = .current) {
        self.client = client
        self.calendar = calendar
    }

    func activeGoalSet(userID: UUID) async throws -> GoalSetSummary? {
        struct ActiveGoalRow: Decodable {
            let goalType: String
            let tdee: Double
            let dailyCalorieTarget: Int
            let effectiveFrom: Date

            enum CodingKeys: String, CodingKey {
                case goalType = "goal_type"
                case tdee
                case dailyCalorieTarget = "daily_calorie_target"
                case effectiveFrom = "effective_from"
            }
        }

        do {
            let rows: [ActiveGoalRow] = try await client
                .from("goal_sets")
                .select("goal_type, tdee, daily_calorie_target, effective_from")
                .eq("user_id", value: userID)
                .is("effective_to", value: nil)
                .limit(1)
                .execute()
                .value

            guard let row = rows.first, let goal = GoalType(rawValue: row.goalType) else {
                return nil
            }

            return GoalSetSummary(
                dailyCalorieTarget: row.dailyCalorieTarget,
                totalDailyEnergyExpenditure: row.tdee,
                goal: goal,
                effectiveFrom: row.effectiveFrom
            )
        } catch {
            throw mapped(error)
        }
    }

    func currentDetails(userID: UUID) async throws -> ProfileDetails? {
        struct ProfileRow: Decodable {
            let displayName: String?
            /// A `date` column, so a bare `1994-03-02` — decoded as text and
            /// parsed, because the client's decoder only understands full
            /// timestamps and throws on this one.
            let birthDate: String?
            let biologicalSex: String?
            let heightCm: Double?
            let mealSchedule: MealSchedule?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case birthDate = "birth_date"
                case biologicalSex = "biological_sex"
                case heightCm = "height_cm"
                case mealSchedule = "meal_schedule"
            }
        }

        struct GoalRow: Decodable {
            let goalType: String
            let activityLevel: String

            enum CodingKeys: String, CodingKey {
                case goalType = "goal_type"
                case activityLevel = "activity_level"
            }
        }

        do {
            let profiles: [ProfileRow] = try await client
                .from("profiles")
                .select("display_name, birth_date, biological_sex, height_cm, meal_schedule")
                .eq("id", value: userID)
                .limit(1)
                .execute()
                .value

            // The open goal set is the current one; `effective_to` is stamped
            // when a new plan supersedes it.
            let goals: [GoalRow] = try await client
                .from("goal_sets")
                .select("goal_type, activity_level")
                .eq("user_id", value: userID)
                .is("effective_to", value: nil)
                .limit(1)
                .execute()
                .value

            guard
                let profile = profiles.first,
                let birthDate = profile.birthDate.flatMap({ ISODay.date(from: $0, in: calendar) }),
                let sex = profile.biologicalSex.flatMap(BiologicalSex.init(rawValue:)),
                let heightCm = profile.heightCm,
                let schedule = profile.mealSchedule,
                let goalRow = goals.first,
                let goal = GoalType(rawValue: goalRow.goalType),
                let activityLevel = ActivityLevel(rawValue: goalRow.activityLevel)
            else { return nil }

            return ProfileDetails(
                displayName: profile.displayName,
                birthDate: birthDate,
                sex: sex,
                heightCm: heightCm,
                activityLevel: activityLevel,
                goal: goal,
                mealSchedule: schedule
            )
        } catch {
            throw mapped(error)
        }
    }

    func hasCompletedOnboarding(userID: UUID) async throws -> Bool {
        let rows: [OnboardingStatusRow] = try await client
            .from("profiles")
            .select("onboarding_completed_at")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value

        // The signup trigger creates the row, but treat a missing row as
        // "not onboarded" rather than an error — routing must still work.
        return rows.first?.onboardingCompletedAt != nil
    }

    func completeOnboarding(_ submission: OnboardingSubmission) async throws {
        let inputs = submission.inputs
        let plan = submission.plan

        let params = CompleteOnboardingParams(
            birthDate: ISODay.string(from: inputs.birthDate, in: calendar),
            biologicalSex: inputs.sex.rawValue,
            heightCm: inputs.heightCm,
            weightKg: inputs.weightKg,
            // normalised() guarantees the shares sum to 1.0, which the RPC
            // rejects the submission over otherwise.
            mealSchedule: submission.mealSchedule.normalised(),
            goalType: inputs.goal.rawValue,
            activityLevel: inputs.activityLevel.rawValue,
            bmr: plan.basalMetabolicRate,
            tdee: plan.totalDailyEnergyExpenditure,
            bmi: plan.bodyMassIndex,
            dailyCalorieTarget: plan.dailyCalorieTarget,
            proteinGTarget: plan.macros.proteinGrams,
            carbsGTarget: plan.macros.carbsGrams,
            fatGTarget: plan.macros.fatGrams,
            displayName: submission.displayName
        )

        do {
            try await client.rpc("complete_onboarding", params: params).execute()
        } catch {
            throw mapped(error)
        }
    }

    func syncTimeZone(_ identifier: String, userID: UUID) async throws -> TimeZoneSyncResult {
        struct TimeZoneRow: Decodable {
            let timeZone: String

            enum CodingKeys: String, CodingKey {
                case timeZone = "time_zone"
            }
        }

        struct TimeZoneUpdate: Encodable {
            let timeZone: String

            enum CodingKeys: String, CodingKey {
                case timeZone = "time_zone"
            }
        }

        let rows: [TimeZoneRow] = try await client
            .from("profiles")
            .select("time_zone")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value

        // No row means handle_new_user() has not run yet; there is nothing to
        // write to, and claiming an update would trigger a pointless rollup
        // rebuild. The next launch retries.
        guard let stored = rows.first?.timeZone else { return .unchanged }
        guard stored != identifier else { return .unchanged }

        try await client
            .from("profiles")
            .update(TimeZoneUpdate(timeZone: identifier))
            .eq("id", value: userID)
            .execute()

        return .updated
    }

    func mealSchedule(userID: UUID) async throws -> MealSchedule {
        struct MealScheduleRow: Decodable {
            let mealSchedule: MealSchedule

            enum CodingKeys: String, CodingKey {
                case mealSchedule = "meal_schedule"
            }
        }

        let rows: [MealScheduleRow] = try await client
            .from("profiles")
            .select("meal_schedule")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value

        guard let schedule = rows.first?.mealSchedule, !schedule.slots.isEmpty else {
            // complete_onboarding rejects an empty schedule, so an onboarded
            // user always has one. Reaching here means the profile is in a
            // state logging cannot invent its way out of.
            throw OnboardingFailure.unexpected("Your meal times are missing. Re-run onboarding from Settings.")
        }
        return schedule.active(on: ISODay.string(from: .now, in: calendar))
    }

    func updateMealSchedule(_ schedule: MealSchedule, userID: UUID) async throws {
        struct MealScheduleUpdate: Encodable {
            let mealSchedule: MealSchedule

            enum CodingKeys: String, CodingKey {
                case mealSchedule = "meal_schedule"
            }
        }

        guard !schedule.slots.isEmpty else {
            throw OnboardingFailure.rejected(reason: "A schedule needs at least one meal.")
        }

        do {
            try await client
                .from("profiles")
                .update(MealScheduleUpdate(mealSchedule: schedule.normalised()))
                .eq("id", value: userID)
                .execute()
        } catch {
            throw mapped(error)
        }
    }

    #if DEBUG
    func resetOnboarding(userID: UUID) async throws {
        /// A nil Optional would simply be omitted from the JSON body, making
        /// the update a no-op, so the null is written explicitly.
        struct ClearOnboarding: Encodable {
            enum CodingKeys: String, CodingKey {
                case onboardingCompletedAt = "onboarding_completed_at"
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeNil(forKey: .onboardingCompletedAt)
            }
        }

        try await client
            .from("profiles")
            .update(ClearOnboarding())
            .eq("id", value: userID)
            .execute()
    }
    #endif

    // MARK: - Helpers

    /// The RPC signals refusal through SQLSTATE codes rather than messages, so
    /// unlike AuthService this can match on something stable.
    private func mapped(_ error: Error) -> OnboardingFailure {
        if error is URLError {
            return .network
        }

        guard let postgrest = error as? PostgrestError else {
            return .unexpected(error.localizedDescription)
        }

        switch postgrest.code {
        case "28000":
            return .notSignedIn
        case "22023", "P0002":
            return .rejected(reason: postgrest.message)
        default:
            return .unexpected(postgrest.message)
        }
    }
}
