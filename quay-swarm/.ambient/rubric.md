**Story Decomposition** (1-5)
Score 1: Stories are not independent. Missing dependencies. Scope too large per story.
Score 2: Stories identified but dependencies incomplete. Some stories overlap in scope.
Score 3: Stories are independent and properly scoped. Dependencies identified. User approved breakdown.
Score 4: Clean decomposition with correct dependency ordering. Stories map to clear technical layers. Estimates provided.
Score 5: Optimal decomposition: each story is independently deliverable, dependencies are minimal and correctly ordered, stories are right-sized for a single agent session, and the breakdown was validated against JIRA acceptance criteria.

**Orchestration** (1-5)
Score 1: Agents spawned without dependency awareness. Concurrency not managed. Failures ignored.
Score 2: Some dependency awareness but agents spawned out of order. No failure recovery.
Score 3: Dependency ordering respected. Concurrency limit enforced. Failures reported to user.
Score 4: Smooth orchestration with proper scheduling, monitoring, and failure recovery. Blocked stories spawned promptly when dependencies resolve.
Score 5: Optimal orchestration: dependency-aware scheduling with maximum parallelism within concurrency limits, proactive failure detection and recovery, efficient monitoring cadence, and clear status reporting throughout.

**Review Coverage** (1-5)
Score 1: No reviews triggered. PRs left unreviewed.
Score 2: Some PRs reviewed but coverage incomplete. Review feedback not tracked.
Score 3: All PRs reviewed. Review verdicts recorded. Changes-requested PRs flagged.
Score 4: All PRs reviewed with thorough feedback. Changes-requested PRs addressed via fix sessions. Review cycle completed.
Score 5: Comprehensive review coverage: all PRs reviewed, CodeRabbit and human feedback addressed, re-reviews triggered after fixes, and all PRs approved before integration.

**Integration Validation** (1-5)
Score 1: No integration testing. Cross-PR conflicts not checked.
Score 2: Basic integration check but incomplete. Migration chain not verified.
Score 3: Integration tester spawned. Alembic heads checked. Basic cross-PR conflict detection.
Score 4: Full integration validation: migration chain clean, no import conflicts, unit and registry tests pass.
Score 5: Comprehensive integration: all cross-story interactions verified, migration chain validated, full test suite passes, performance regressions checked, and integration report generated.
