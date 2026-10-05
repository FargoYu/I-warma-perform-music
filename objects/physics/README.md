# Physics contract layer — coordinated production physics (Stage F cutover)

Production Warma/Giraffe now expose `collect_motion_intent()` and
`apply_motion_result()`. Add `actor_motion_driver.gd` as a child of a prepared room
and explicitly call `configure(room, actors, terrain, elevators)`. It validates exact geometry
and rejects unregistered legacy Elevators before binding anything. On success it disables old
physics callbacks and schedules one coordinated physics frame. It refuses actors
already bound to another driver. Stage F performed the production cutover:
all thirteen authored gameplay rooms set `coordinated_physics_room = true`, and
`rooms/room.gd` collects the room-scoped Player, Giraffe and Elevator groups and
passes them to `configure()`. `title.tscn` has no physics participant.

The Stage A+B default-off room factory and explicit single-driver `step()` API are
unchanged for evidence reproduction. The new driver owns a separate room-local
MotionWorld and uses `step_frame()`; never activate both APIs on the same actors.

## Boundaries

- `logical_bounds.gd`: finite positive scalar rectangles, with shared Y anchors for
  chain proposals. `Rect2`/`Vector2` conversions are query/render representations.
- `motion_contract.gd`: displacement intents/results and role/pair policy. Local
  contact, attached carry and anchored ancestry are separate facts; there is no
  mass/load policy for vertical chains.
- `contact_resolver.gd`: pure axis contact planes, invalid-input diagnosis and
  proposals for an explicitly assembled required vertical group. Positive lips
  block, tangent faces do not. Nothing centers or depenetrates an actor.
- `support_graph.gd`: exact contacts, explicit detach, ancestry and iterative
  required-chain collection. With frame intents, primary support is the smallest
  down-positive Y request (highest prospective plane), then stable ID. Without
  intents, the original Stage A+B stable-ID contract remains unchanged.
- `scene_geometry.gd`: read-only adapters for actual Warma/Giraffe/Block scenes,
  including Warma's asymmetric polygon and actual Giraffe root transform. It also
  classifies GroundProbe, HeadProbe and Nozzle as nonsolid gameplay queries/marker.
- `terrain_adapter.gd`: read-only extraction of the audited exact rectangular
  tile contract. It refuses legacy inset terrain instead of changing it.
- `motion_query.gd`: native mask 7 body queries, excluding Areas and the source RID.
  Collider identity maps to registered bodies or cells of a real TileMapLayer.
  A closed scalar swept-AABB scan supplements native candidates at tangent faces
  and after same-frame commits. This deliberately exhaustive small-world scan adds
  no discovery halo or penetration epsilon. Native unknown solids and result-limit
  overflow reject the transaction, never silently truncate it.
- `motion_world.gd`: owns committed logical geometry and real actor root writes.
  It keeps Stage B `step()` and adds atomic full-frame `step_frame()`, refusing
  active legacy callbacks, external writes and stale registrations.
- `frame_resolver.gd`: works on proposed state, orders X by stable IDs and Y by
  support depth / smallest Y request / Warma-first role / stable ID, carries required riders, acquires
  upward Warma→Giraffe contacts and caps the whole chain at a blocking plane. Full
  frame validation precedes the single node commit. No horizontal pushing.
- `actor_motion_driver.gd`: captures support facts, calls production actor intent
  methods, resolves the frame and delivers results. Input, gravity, facing, timers,
  equipment, death and music remain in actor gameplay code. Unregisters disappeared
  bodies, inherits room freeze and rejects existing or newly added unbound Elevators.
- `elevator_geometry.gd`: anchored scalar length, direction, logical rectangle and
  native identity for real direction-specific Elevator scenes. Rejects external
  mutation of committed shapes, dimensions, root transforms or layers.
- `elevator_transaction.gd`: working-state shape changes after actor X and before
  actor Y. UP uses the Stage C required-rider graph and common legal displacement.
  Only rod/terrain overlap is exempt; actor/rod and rod/rod pairs remain solid.

## Velocity and support policy

X contact clears the requesting actor's X velocity. A blocked vertical chain clears
Y velocity for every member. An unblocked carried/lifted member inherits its source's
selected Y velocity; its independent fall step is consumed. Free motion keeps its
gameplay-integrated velocity. Contact planes determine blockage, not floating-point
subtraction of traveled distance. This preserves ballistic velocity when support is
lost and prevents a second gravity step on carried actors.

Warma uses local attached foot contact for jump eligibility even on a falling stack,
matching the old GroundProbe semantics; terrain ancestry stays separately exposed.
Held J renews the request, release cancels it, and explicit coyote duration is 0.10s.
Jumping detaches Warma. Giraffe's own upward impulse detaches it; inherited negative
velocity alone does not. Lifted riders follow Warma's cut/apex until separation,
rather than retaining the old independently preloaded head-bump impulse. External
Giraffe impulses still use the existing exported mass as before; stack depth/mass
does not scale Warma's trajectory.

## Running the isolated integration fixture

`tests/phase3_production/integration_fixture.tscn` opts in. Its helper methods
instantiate the original actor/terrain PackedScenes. Only its actor instances have
physics callbacks disabled. Only its duplicated terrain resources become 16×16.
No scene serialization, root identity, layer/mask, actor shape or sensor is replaced.

The Stage A test drives pure data contracts, including common displacement. The
Stage B test drives real roots with scripted intents, rather than translating player
input or calling the old controller. Use `tests/phase3_production/run_checkpoint.py`
to run in the recorded source snapshot and preserve Phase 1/2's overwriting outputs.
See the Stage A+B report for commands, counts, known legacy failures and evidence.

Stage C controller tests live separately in `tests/stage_c/`; their runner preserves
all prior research and A+B outputs. They exercise the production actor methods and
also the native scheduler, rather than supplying artificial movement intents.

## Explicitly deferred

The real bound Elevator's root is fixed while its shape mutates; UP's support plane
moves during extension/retraction, while DOWN/LEFT/RIGHT tops remain fixed. Rods
may overlap terrain, but actors cannot, and another rod or uncarried actor blocks
growth. Uncarried obstructions preserve the old whole-height-step stall/retry
policy; attached riders cap the common displacement at their nearest blocking
plane. No clearance or snap is used. A bound `set_height()` queues a target; it
does not mutate geometry. Button activation retains normal/starts-extended target
inversion. Retraction of an UP support carries its attached actors downward;
horizontal retraction changes support coverage and never drags actors along X.

MotionWorld validates all proposals before publishing rod shapes and actor roots.
It then performs a zero-motion, margin-zero PhysicsServer body test solely to
drain pending shape-bound updates before native direct-space queries. The test
result is discarded; it does not resolve or commit motion. This explicit backend
publication barrier is covered by same-frame point, shape and ShapeCast tests.
Do not replace it with padding or a delayed snap. See the Stage D report for the
failed synchronization evidence and engine-version limitation.

The authored-room rollout is complete (Stage F). Broader sensor/lifecycle
scheduling and global terrain normalization are still deferred: the shared
`objects/tileset.tres` keeps its legacy inset and each coordinated room
localizes its own deep copy at activation. Unlisted Elevators remain rejected so
the preserved Stage C compatibility guard still holds.

Unsupported shape types, transformed colliders and TileSet alternatives fail with
diagnostics. No global terrain normalization, actor size reduction or legacy-hack
removal is included; the authored-room rollout localizes terrain per room instead
of mutating the shared resource. Both motion skin and query margin are zero;
original Warma native safe margin remains untouched. Bound
actors never read those probes or invoke native movement, tight-gap alignment,
mask removal or Elevator snap. Probe nodes stay for legacy rooms; Nozzle remains
the active projectile spawn marker. No legacy source path was deleted.
