package org.bu.jenkins.mvc.model;

import software.amazon.awssdk.services.cloudformation.model.Stack;
import software.amazon.awssdk.services.cloudformation.model.Tag;

public class CloudFormationStack {

	private Stack stack;
	
	public CloudFormationStack(Stack stack) {
		this.stack = stack;
	}
	
	/**
	 * The way to determine the baseline landscape of a stack is to check for the corresponding tag on the stack.
	 * @return
	 */
	public String getBaseline() {
		String baseline = null;
		if(stack.hasTags()) {
			for(Tag tag : stack.tags()) {
				if("baseline".equalsIgnoreCase(tag.key())) {
					if(Landscape.isBaseline(tag.value())) {
						baseline = tag.value();
						break;
					}
				}
			}
		}
		return baseline;
	}

	/**
	 * The way to determin the landscape of a stack is to check for the corresponding tag on the stack.
	 * Alternatively, the stack name may be suffixed with the name of the landscape.
	 * @return
	 */
	public String getLandscape() {
		String landscape = null;
		if(stack.hasTags()) {
			for(Tag tag : stack.tags()) {
				if("landscape".equalsIgnoreCase(tag.key())) {
					landscape = tag.value();
				}
			}
		}
		if(landscape == null) {
			if(stack.stackName().matches(".*\\-[^\\-]+$")) {
				String[] parts = stack.stackName().split("\\-");
				landscape = parts[parts.length - 1];
			}
		}
		return landscape;
	}
	
	public Stack getStack() {
		return stack;
	}
}
