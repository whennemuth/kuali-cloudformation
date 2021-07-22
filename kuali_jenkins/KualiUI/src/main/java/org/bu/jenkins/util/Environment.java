package org.bu.jenkins.util;

public interface Environment {

	boolean containsKey(String key);

	String get(String key);

}
