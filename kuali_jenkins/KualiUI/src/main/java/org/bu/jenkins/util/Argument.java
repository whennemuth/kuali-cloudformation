package org.bu.jenkins.util;

public class Argument {

	public static boolean isMissing(Object o) {
		if(o == null || o.toString().isBlank()) return true;
		return false;
	}
}
