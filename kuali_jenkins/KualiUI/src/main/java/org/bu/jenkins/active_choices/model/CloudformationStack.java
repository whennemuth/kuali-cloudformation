package org.bu.jenkins.active_choices.model;

import software.amazon.awssdk.services.cloudformation.model.Stack;
import software.amazon.awssdk.services.cloudformation.model.StackSummary;

public class CloudformationStack extends AbstractAwsResource {

	private Stack stack;
	private StackSummary summary;
	
	public CloudformationStack() {
		super();
	}
	public CloudformationStack setStack(Stack stack) {
		this.stack = stack;
		this.arn = stack.stackId();
		this.name = stack.stackName();
		return this;
	}
	public CloudformationStack setStackSummary(StackSummary summary) {
		this.summary = summary;
		this.arn = summary.stackId();
		this.name = summary.stackName();
		return this;
	}
	public Stack getStack() {
		return stack;
	}
	public StackSummary getStackSummary() {
		return summary;
	}
	public boolean hasSummary() {
		return this.summary != null;
	}
	public boolean hasStack() {
		return this.stack != null;
	}
	public CloudformationStack put(Object stackObj) {
		if(stackObj instanceof Stack)
			this.stack = (Stack) stackObj;
		else if(stackObj instanceof StackSummary)
			this.summary = (StackSummary) stackObj;
		return this;
	}
	public String getStackId() {
		if(stack != null)
			return stack.stackId();
		if(summary != null)
			return summary.stackId();
		return null;
	}
}
