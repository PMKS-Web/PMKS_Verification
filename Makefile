# Local entry points for the checks that do not need MATLAB.
#
# Everything here runs on a laptop. Only the MATLAB candidate genuinely requires
# the GitHub runner, so exhausting these first is what keeps CI iteration short.

PMKS_COMMIT := 644b26c75b07182ce04dc6466cfec74ee4130c93
PMKS_ROOT   := .external/PMKS
V1_ROOT     := reference-data/v1

.PHONY: help refresh-hashes validate oracle check clean-candidate

help:
	@echo 'refresh-hashes  Recompute source hashes after editing shared sources'
	@echo 'validate        Schema, case set, trust labels, source hashes, dynamics'
	@echo 'oracle          Run the PMKS oracle against the committed cases'
	@echo 'check           validate + oracle'

# Recompute the content hashes recorded in reference-data.
#
# Editing CommonUtils/*.m, verification/*.m, or oracle/pmks/* invalidates
# recorded hashes for every case, including ones whose own source never moved --
# matlab_files() hashes the shared scripts alongside each case folder, and the
# oracle adapter hash covers all of oracle/pmks. Without this target that failure
# surfaces late, in a different CI job, naming an unrelated case.
#
# Requires the pinned PMKS fork: write_source_metadata.py silently writes null
# PMKS provenance when --pmks-root is absent, which would be worse than the
# problem it is fixing.
refresh-hashes: $(PMKS_ROOT)
	python3 tools/write_source_metadata.py \
	  --root $(V1_ROOT) --repo-root . --pmks-root $(PMKS_ROOT)
	python3 tools/validate_v1.py --require-sources
	@echo
	@echo 'Hashes refreshed. Review the diff before committing: only'
	@echo 'source-metadata.json files should have changed.'

validate:
	python3 tools/validate_v1.py --require-sources
	python3 tools/check_dynamics.py --root $(V1_ROOT)

oracle: $(PMKS_ROOT)
	dotnet run --project oracle/pmks/PmksOracle.csproj -c Release -- \
	  --cases-root $(V1_ROOT)/cases \
	  --output-root artifacts/candidate/reference-data/v1

check: validate oracle

# Pinned fork, not DesignEngrLab upstream: the oracle and every recorded
# pmks_source_content_sha256 are this fork at this commit.
$(PMKS_ROOT):
	git clone https://github.com/PMKS-Web/PMKS $(PMKS_ROOT)
	git -C $(PMKS_ROOT) checkout $(PMKS_COMMIT)

clean-candidate:
	rm -rf artifacts/candidate
