import DandelionWebSockets: AbstractBackoff, Backoff, RandomizedBackoff,
                            reset, backoff_min, backoff_max

type FakeBackoff <: AbstractBackoff
    values::Vector{Float64}
    min::Float64
    max::Float64
    i::Int

    FakeBackoff(values::Vector{Float64}, min::Float64, max::Float64) = new(values, min, max, 1)
end

function call(b::FakeBackoff)
    v = b.values[b.i]
    b.i += 1
    v
end

backoff_min(b::FakeBackoff) = b.min
backoff_max(b::FakeBackoff) = b.max

facts("Reconnect") do
    context("Backoff") do
        min = 30.0
        max = 200.0
        backoff_range = max - min
        backoff = Backoff(min, max)

        values = [backoff() for i in range(1, 12)]

        # The first three attempts won't reach half the backoff range.
        for i in range(1, 3)
            @fact values[i] < 0.5 * backoff_range --> true
        end

        # After twelve attempts the backoff is over 90% of the backoff range.
        @fact values[12] > 0.9 * backoff_range --> true
    end

    context("Backoff reset") do
        backoff = Backoff(0.0, 100.0)
        values = [backoff() for i in range(1, 12)]
        reset(backoff)
        @fact backoff() --> 0.0
    end

    context("Backoff limits") do
        min = 30.0
        max = 200.0
        backoff = Backoff(min, max)
        values = [backoff() for i in range(1, 100)]
        for v in values
            @fact v >= min --> true
            @fact v <= max --> true
        end

        @fact backoff_min(backoff) --> min
        @fact backoff_max(backoff) --> max
    end

    context("RandomizedBackoff") do
        rmin = 5.0
        rmax = 13.0
        r = 5.0
        backoff = FakeBackoff([5.0, 7.0, 9.0, 12.0, 13.0], rmin, rmax)
        expected_rng_values = [1.0, -3.0, 3.0, 1.0, 5.0]
        rng = FakeRNG{Float64}([x/(2*r) + 0.5 for x in expected_rng_values])
        expected = [6.0, 5.0, 12.0, 13.0, 13.0]

        rand_backoff = RandomizedBackoff(backoff, rng, r)
        values = [rand_backoff() for i in range(1, 5)]
        for i in range(1, 5)
            @fact values[i] --> roughly(expected[i])
        end
    end
end