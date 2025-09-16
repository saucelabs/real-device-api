package com.saucelabs.rdc.openapi.model;

/**
 * Represents the lifecycle states of a device session.
 */
public enum ApiSessionState {
	PENDING,
	CREATING,
	ACTIVE,
	CLOSING,
	CLOSED,
	ERRORED
}
