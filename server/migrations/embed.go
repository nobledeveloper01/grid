// Package migrations carries the schema, compiled into the binary.
//
// It exists as a package because `go:embed` can only reach files at or below
// the directory it is declared in — so embedding `migrations/*.sql` from
// `internal/store` is not possible, and the alternative is scattering the SQL
// under the package that happens to read it. The schema stays where somebody
// looking for the schema would look.
//
// Embedding rather than shipping the files means the binary applies its own
// schema. A container that has the code but not the .sql files is not a
// failure mode this can have.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
