package outbox

import (
	"context"
	"errors"
	"testing"
)

func TestNoopHandlerIsIdempotent(t *testing.T) {
	handler := NoopHandler{}
	event := Event{ID: "event-1", EventType: "notification.created", Payload: []byte(`{"id":"n1"}`)}
	if err := handler.Handle(context.Background(), event); err != nil {
		t.Fatal(err)
	}
	if err := handler.Handle(context.Background(), event); err != nil {
		t.Fatal(err)
	}
}

func TestMinCapsBackoffExponent(t *testing.T) {
	if min(9, 8) != 8 || min(3, 8) != 3 {
		t.Fatal(errors.New("min returned unexpected value"))
	}
}
