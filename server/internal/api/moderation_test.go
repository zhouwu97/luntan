package api

import (
	"net/http/httptest"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestHasAnyPermissionChecksGlobalRolePermission(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(regexp.QuoteMeta(`
		SELECT EXISTS (
			SELECT 1 FROM user_roles ur
			JOIN role_permissions rp ON rp.role_id = ur.role_id
			JOIN permissions p ON p.id = rp.permission_id
			WHERE ur.user_id = $1 AND p.name = $2
		)`)).WithArgs("user-1", "report.review").WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	if !(&Server{db: db}).hasAnyPermission(httptest.NewRequest("GET", "/api/v1/moderation/cases", nil), "user-1", "report.review") {
		t.Fatal("hasAnyPermission returned false for an allowed user")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
