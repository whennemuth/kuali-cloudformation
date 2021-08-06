package org.bu.jenkins.mvc.view;

/**
 * An interface for views specific to jenkins active choices parameter fields.
 * 
 * @author wrh
 *
 */
public interface ParameterView extends View {

	boolean isReadOnly();
	
	String getResolverPrefix();
}